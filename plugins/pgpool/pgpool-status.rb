#!/usr/bin/env ruby
#
# PGPool status Plugin
#
# This plugin attempts to login to postgres with provided credentials.
#
# Copyright 2015 tuenti Eng (Javier Juarez jjuarez _AT_ tuenti.com)
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'mixlib/shellout'

#
# = class: PCPNodeInfo, PORO
class PCPNodeInfo
  INITIALIZING      = 0 # This state is only used during the initialization.
  UP_NO_CONNECTIONS = 1 # Node is up. No connections yet.
  UP                = 2 # Node is up. Connections are pooled.
  DOWN              = 3 # Node is down.

  def self.build_from_raw_data(id, command_raw_data)
    host, port, status, weight = command_raw_data.split(' ')

    PCPNodeInfo.new(id, host, port, weight, status)
  end

  def initialize(id, host, port, weight, status)
    @id     = id
    @host   = host
    @port   = port.to_i
    @weight = weight.to_f
    @status = status.to_i

    self
  end

  attr_reader :id, :host, :port, :weight, :status

  def up?
    (@status == UP || @status == UP_NO_CONNECTIONS)
  end

  def down?
    @status == DOWN
  end
end

#
# = class: PCPResponse
class PCPResponse
  OK        = 0
  UNKNOWN   = 1    # Unknown Error (should not occur)
  EOF       = 2    # EOF Error
  NOMEM     = 3    # Memory shortage
  READ      = 4    # Error while reading from the server
  WRITE     = 5    # Error while writing to the server
  TIMEOUT   = 6    # Timeout
  INVAL     = 7    # Argument(s) to the PCP command was invalid
  CONN      = 8    # Server connection error
  NOCONN    = 9    # No connection exists
  SOCK      = 10   # Socket error
  HOST      = 11   # Hostname resolution error
  BACKEND   = 12   # PCP process error on the server (specifying an invalid ID, etc.)
  AUTH      = 13   # Authorization failure

  def initialize(node_id, command)
    @status    = command.exitstatus
    @node_info = @status == 0 ? PCPNodeInfo.build_from_raw_data(node_id, command.stdout) : command.stderr

    self
  end

  attr_reader :status, :node_info

  def success?
    @status == OK
  end
end

#
# = class: PCPWraper, a simple wrapper over de pgPool management command line utilities
class PCPWrapper
  DEFAULT_TIMEOUT    = 10
  DEFAULT_PREFIX     = '/usr/sbin'
  PCP_NODE_COUNT_EXE = 'pcp_node_count'
  PCP_NODE_INFO_EXE  = 'pcp_node_info'
  INVALID_NODE_ID    = 99

  private

  def extract_number_of_nodes
    pcp_node_count = Mixlib::ShellOut.new(@pcp_node_count_command)

    pcp_node_count.run_command
    pcp_node_count.error!
    pcp_node_count.stdout.to_i
  end

  public

  def initialize(parameters)
    parameters = { prefix: DEFAULT_PREFIX, timeout: DEFAULT_TIMEOUT }.merge(parameters)

    @hostname  = parameters[:hostname]
    @port      = parameters[:port]
    @user      = parameters[:user]
    @password  = parameters[:password]
    @timeout   = parameters[:timeout]

    @pcp_command_options    = "#{@timeout} #{@hostname} #{@port} #{@user} #{@password}"
    @pcp_node_count_command = "#{File.join(parameters[:prefix], PCP_NODE_COUNT_EXE)} #{@pcp_command_options}"
    @pcp_node_info_command  = "#{File.join(parameters[:prefix], PCP_NODE_INFO_EXE)} #{@pcp_command_options}"
    @number_of_nodes        = extract_number_of_nodes

    self
  end

  attr_reader :number_of_nodes

  def valid_node_id?(node_id)
    node_id >= 0 && node_id < @number_of_nodes
  end

  def node_information(node_id)
    fail("Invalid node id(#{node_id}) must be between 0 and #{@number_of_nodes - 1}") unless valid_node_id?(node_id)

    pcp_node_info = Mixlib::ShellOut.new("#{@pcp_node_info_command} #{node_id}")

    pcp_node_info.run_command
    pcp_node_info.error!

    PCPResponse.new(node_id, pcp_node_info)
  end

  def nodes_information
    @number_of_nodes.times.map { |node_id| node_information(node_id) }
  end
end

# A bit of spicy monkey patching
class String
  def percentage?
    /\A[-+]?\d+\z/ =~ self && to_i >= 0 && to_i <= 100
  end
end

#
# = class: CheckPGPool the sensu check
class CheckPGPool < Sensu::Plugin::Check::CLI
  DEFAULT_TIMEOUT           = 10
  DEFAULT_HOSTNAME          = 'localhost'
  DEFAULT_PORT              = 9898
  DEFAULT_WARNING_THRESOLD  = 50
  DEFAULT_CRITICAL_THRESOLD = 100

  option :timeout,
         description: 'PCP command timemout',
         short:       '-t TIMEOUT',
         long:        '--timeout TIMEOUT',
         default:     DEFAULT_TIMEOUT

  option :hostname,
         description: 'PCP Hostname',
         short:       '-h HOST',
         long:        '--hostname HOSTNAME',
         default:     DEFAULT_HOSTNAME

  option :port,
         description: 'PCP port',
         short:       '-P PORT',
         long:        '--port PORT',
         default:     DEFAULT_PORT

  option :user,
         description: 'PCP User',
         short:       '-u USER',
         long:        '--user USER'

  option :password,
         description: 'PCP Password',
         short:       '-p PASSWORD',
         long:        '--password PASSWORD'

  option :warning,
         description: 'Warning threshold',
         short:       '-w PERCENTAGE',
         long:        '--warning PERCENTAGE',
         default:     DEFAULT_WARNING_THRESOLD

  option :critical,
         description: 'Critical threshold',
         short:       '-c PERCENTAGE',
         long:        '--critical PERCENTAGE',
         default:     DEFAULT_CRITICAL_THRESOLD

  def run
    unknown("Invalid warning threshold value: #{config[:warning]}")   unless config[:warning].percentage?
    unknown("Invalid critical threshold value: #{config[:critical]}") unless config[:critical].percentage?

    pcp_wrapper           = PCPWrapper.new(config)
    pcp_status            = pcp_wrapper.nodes_information
    total_nodes           = pcp_wrapper.number_of_nodes
    nodes_down            = pcp_status.count { |n| n.node_info.down? }
    percentage_nodes_down = nodes_down * 100 / total_nodes

    critical("#{percentage_nodes_down}% of the nodes are down (#{nodes_down}/#{total_nodes})") if percentage_nodes_down >= config[:critical].to_i
    warning("#{percentage_nodes_down}% of the nodes are down (#{nodes_down}/#{total_nodes})")  if percentage_nodes_down >= config[:warning].to_i
    ok("#{percentage_nodes_down}% of the nodes are down")
  rescue => run_exception
    unknown "Error: #{run_exception.message}"
  end
end
