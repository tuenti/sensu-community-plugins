#!/usr/bin/env ruby
#
# Vertica status Plugin
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
require 'vertica'

#
# = class: CheckVerticaCluster the sensu check
class CheckVerticaCluster < Sensu::Plugin::Check::CLI

  DEFAULT_CLUSTER_QUERY = 'SELECT * FROM nodes;'.freeze

  option :host,
         description: 'Vertica hostname',
         short:       '-h HOST',
         long:        '--host HOSTNAME'

  option :port,
         description: 'Vertica port',
         short:       '-P PORT',
         long:        '--port PORT'

  option :user,
         description: 'Vertica user',
         short:       '-u USER',
         long:        '--user USER'

  option :password,
         description: 'Vertica password',
         short:       '-p PASSWORD',
         long:        '--password PASSWORD'

  option :database,
         description: 'Vertica database',
         short:       '-d DATABASE',
         long:        '--database DATABASE'

  option :debug,
         description: 'Debug mode',
         short:       '-D',
         long:        '--debug',
         default:     false


  def ok?(nodes)
    nodes.rows.all? { |node| node[:node_state] == 'UP' }
  end

  def warning?(nodes)
    nodes.rows.any? { |node| node[:node_state] =~ /(INITIALIZING|SHUTDOWN|READY|RECOVERING)/ }
  end

  def critical?(nodes)
    nodes.rows.any? { |node| node[:node_state] == 'DOWN' }
  end

  def get_roten_nodes(nodes)
    nodes.rows.select { |node| node[:node_state] =~ /(DOWN|INITIALIZING|SHUTDOWN|READY|RECOVERING)/ }.map { |node| node[:node_name] }
  end

  def get_vertica_data(vertica_query)

    vertica_connection = Vertica.connect(
      :host      => config[:host],
      :port      => config[:port],
      :user      => config[:user],
      :password  => config[:password],
      :database  => config[:database],
      :row_style => :hash
    )

    vertica_connection.query(vertica_query)
  end

  def run

    nodes = get_vertica_data(DEFAULT_CLUSTER_QUERY)

    critical("The cluster has node(s) DOWN: (#{get_roten_nodes(nodes)})") if critical?(nodes)
    warning("The cluster has node(s) with undesirable states (#{get_roten_nodes(nodes)})") if warning?(nodes)
    ok("Your cluster is working like a charm") if ok?(nodes)
  rescue => run_exception
    unknown("Error: #{run_exception.message} nodes status: #{get_roten_nodes(nodes)}")
  end
end
