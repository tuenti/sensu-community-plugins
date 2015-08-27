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

  INITIALIZING      = 0 # This state is only used during the initialization. PCP will never display it.
  UP_NO_CONNECTIONS = 1 # Node is up. No connections yet.
  UP                = 2 # Node is up. Connections are pooled.
  DOWN              = 3 # Node is down.

  def self.build_from_raw_data(id, data)

    host, port, status, weight = data.split(' ')

    PCPNodeInfo.new(id, host, port, weight, status)
  end

  attr_reader :id, :host, :port, :weight, :status

  def initialize(id, host, port, weight, status)

    @id     = id
    @host   = host
    @port   = port.to_i
    @weight = weight.to_f
    @status = status.to_i
 
    self
  end

  def is_up?
    (@status == UP || @status == UP_NO_CONNECTIONS)
  end

  def is_down?
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

  attr_reader :status, :node_info

  def initialize(node_id, command)

    @status    = command.exitstatus
    @node_info = if @status == 0 
      PCPNodeInfo.build_from_raw_data(node_id, command.stdout)
    else 
      command.stderr
    end

    self
  end

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

  attr_reader :number_of_nodes

  def initialize(parameters)

    parameters = { 
      prefix:  DEFAULT_PREFIX,
      timeout: DEFAULT_TIMEOUT 
    }.merge(parameters)

    @hostname            = parameters[:hostname]
    @port                = parameters[:port]
    @user                = parameters[:user]
    @password            = parameters[:password]
    @timeout             = parameters[:timeout]
    @pcp_command_options = "#{@timeout} #{@hostname} #{@port} #{@user} #{@password}"
    @pcp_node_count_exe  = File.join(parameters[:prefix], PCP_NODE_COUNT_EXE)
    @pcp_node_info_exe   = File.join(parameters[:prefix], PCP_NODE_INFO_EXE)
    @number_of_nodes     = get_number_of_nodes 

    self
  end

  def get_number_of_nodes

    pcp_node_count = Mixlib::ShellOut.new("#{@pcp_node_count_exe} #{@pcp_command_options}")

    pcp_node_count.run_command
    pcp_node_count.error!
    pcp_node_count.stdout.to_i
  end

  def is_a_valid_node_id?(node_id)
    (0..@number_of_nodes-1) === node_id
  end

  def get_node_information(node_id)

    raise StandardError.new("Invalid node id(#{node_id}) must be between 0 and #{@number_of_nodes-1}") unless is_a_valid_node_id?(node_id)

    pcp_node_info = Mixlib::ShellOut.new("#{@pcp_node_info_exe} #{@pcp_command_options} #{node_id}")
    pcp_node_info.run_command
    pcp_node_info.error!

    PCPResponse.new(node_id, pcp_node_info) 
  end

  def get_all_nodes_information

    @number_of_nodes.times.map { |id| get_node_information(id) }
  end
end


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
         long:        '--hostname HOST',
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
         short:       '-p PASS',
         long:        '--password PASS'

  option :warning,
         description: 'Warning threshold',
         short:       '-w PERCENTAGE',
         long:        '--warning PERCENTAJE',
         default:     DEFAULT_WARNING_THRESOLD

  option :critical,
         description: 'Critical threshold',
         short:       '-c PERCENTAGE',
         long:        '--critical PERCENTAJE',
         default:     DEFAULT_CRITICAL_THRESOLD
  
  def run

    pcp_wrapper           = PCPWrapper.new(config)
    pcp_status            = pcp_wrapper.get_all_nodes_information
    nodes_down            = pcp_status.count { |n| n.data.is_down? }
    percentage_nodes_down = nodes_down * 100 / pcp_wrapper.number_of_nodes

    critical "#{percentage_nodes_down}% of the nodes are down" if percentage_nodes_down >= config[:critical].to_i
    warning  "#{percentage_nodes_down}% of the nodes are down" if percentage_nodes_down >= config[:warning].to_i
    ok       "#{percentage_nodes_down}% of the nodes are down"
  rescue => e
    unknown "Error: #{e.message}"
  end
end
