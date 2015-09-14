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
require 'pgpool/pcpwrapper'

#
# = class: CheckPGPool the sensu check
class CheckPGPool < Sensu::Plugin::Check::CLI
  DEFAULT_TIMEOUT           = 10
  DEFAULT_HOSTNAME          = 'localhost'
  DEFAULT_PORT              = 9898
  DEFAULT_WARNING_THRESOLD  = '50'
  DEFAULT_CRITICAL_THRESOLD = '100'

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

    pcp_wrapper           = PGPool::PCPWrapper.new(config)
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
