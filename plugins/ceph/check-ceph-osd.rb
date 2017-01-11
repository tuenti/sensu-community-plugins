#! /usr/bin/env ruby
#
# check-ceph
#
# DESCRIPTION:
#   #YELLOW
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   ceph client
#
# USAGE:
#   #YELLOW
#
# NOTES:
#   Runs 'ceph health' command(s) to report health status of ceph
#   cluster. May need read access to ceph keyring and/or root access
#   for authentication.
#
#   Using -u (--user) option allows to set the username to connect with
#   the ceph cluster. By default the user is admin.
#
#   Using -i (--ignore-flags) option allows specific options that are
#   normally considered Ceph warnings to be overlooked and considered
#   as 'OK' (e.g. noscrub,nodeep-scrub).
#
#   Using -d (--detailed) and/or -o (--osd-tree) will dramatically increase
#   verboseness during warning/error reports, however they may add
#   additional insights to cluster-related problems during notification.
#
# LICENSE:
#   Copyright 2013 Brian Clark <brian.clark@cloudapt.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'timeout'
require 'English'
require 'json'

class CheckCephOSDHealth < Sensu::Plugin::Check::CLI
  option :user,
         description: 'Client name for authentication',
         short: '-u USER',
         long: '--user',
         proc: proc { |u| " --user #{u}" }

  option :monitor,
         description: 'Optional monitor IP',
         short: '-m MON',
         long: '--monitor',
         proc: proc { |m| " -m #{m}" }

  option :cluster,
         description: 'Optional cluster name',
         short: '-c NAME',
         long: '--cluster',
         proc: proc { |c| " --cluster=#{c}" }

  option :timeout,
         description: 'Timeout (default 10)',
         short: '-t SEC',
         long: '--timeout',
         proc: proc(&:to_i),
         default: 10

  option :osd_tree,
         description: 'Show OSD tree on warns/errors (verbose!)',
         short: '-o',
         long: '--osd-tree',
         boolean: true,
         default: false

  option :all,
         description: 'Check percentage of all the OSDs in the cluster',
         long: '--all',
         boolean: true,
         default: false

  option :per_host,
         description: 'Check percentage of OSDs from each host',
         long: '--per_host',
         boolean: true,
         default: false

  option :warn,
         short: '-w WARN',
         long: '--warn WARN',
         description: 'Warn if PERCENT or more osds are down or out',
         proc: proc(&:to_f),
         default: 10

  option :crit,
         short: '-c',
         long: '--critical CRIT',
         description: 'Critical if PERCENT or more osds are down or out',
         proc: proc(&:to_f),
         default: 25

  option :show_stderr,
         description: 'Show standard error from ceph commands',
         long: '--stderr',
         boolean: true,
         default: false

  def run_cmd(cmd)
    pipe, status = nil
    begin
      cmd += config[:cluster] if config[:cluster]
      cmd += config[:user] if config[:user]
      cmd += config[:monitor] if config[:monitor]
      cmd += ' 2>&1' if config[:show_stderr]
      Timeout.timeout(config[:timeout]) do
        pipe = IO.popen(cmd)
        Process.wait(pipe.pid)
        status = $CHILD_STATUS.exitstatus
      end
    rescue Timeout::Error
      begin
        Process.kill(9, pipe.pid)
        Process.wait(pipe.pid)
      rescue Errno::ESRCH, Errno::EPERM
        # Catch errors from trying to kill the timed-out process
        # We must do something here to stop travis complaining
        critical 'Execution timed out'
      ensure
        critical 'Execution timed out'
      end
    end
    output = pipe.read
    critical "Command '#{cmd}' returned no output" if output.to_s == ''
    critical output unless status == 0
    output
  end

  def get_data(cmd)
    result = run_cmd(cmd + ' --format json')
    data = JSON.parse(result)
  end

  def general_stats
    data = get_data('ceph osd stat')
    total_osds = data['num_osds'].to_f
    up_osds = data['num_up_osds'].to_f
    in_osds = data['num_in_osds'].to_f
    remapped_pgs = data['num_remapped_pgs']
    full = data['full']
    nearfull = data['nearfull']

    down_osds = 100 * (total_osds - up_osds) / total_osds
    out_osds = 100 * (total_osds - in_osds) / total_osds
    return down_osds, out_osds
  end

  def osd_stats
    data = get_data('ceph osd tree')
    hosts = {}
    osds = {}
    data['nodes'].each do |node|
      if node['type'] == 'host'
        hosts[node['name']] = node
        hosts[node['name']]['total_daemons'] = node['children'].size
        hosts[node['name']]['number_down'] = 0
        hosts[node['name']]['number_out'] = 0
        hosts[node['name']]['percentage_down'] = 0.0
        hosts[node['name']]['percentage_out'] = 0.0
      end

      osds[node['id']] = node if node['type'] == 'osd'
    end

    hosts.each do |host, metrics|
      metrics['children'].each do |daemon|
        metrics['number_down'] += 1 if osds[daemon]['status'] == 'down'
        metrics['number_out'] += 1 if osds[daemon]['status'] == 'down'
      end
      metrics['percentage_down'] = 100.0 * metrics['number_down'].to_f / metrics['total_daemons']
      metrics['percentage_out'] = 100.0 * metrics['number_out'].to_f / metrics['total_daemons']
    end

    hosts
  end

  def run
    message = ''
    down_osds, out_osds = general_stats()
    osd_hosts = osd_stats()

    if config[:all]
      message = "OSDs down #{down_osds.round(2)}% - OSDs out #{out_osds.round(2)}%\n"
    elsif config[:per_host]
      osd_hosts.each do |host, values|
        message = "Host: #{host} OSDs Down: #{values['percentage_down'].round(2)}%\n"
      end
    end

    message += run_cmd('ceph osd tree') if config[:osd_tree]

    if config[:all]
      critical message if down_osds > config[:crit] or out_osds > config[:crit]
      warning message if down_osds > config[:warn] or out_osds > config[:warn]
    elsif config[:per_host]
      critical message if osd_hosts.any? { |host, metrics| metrics['percentage_down'] > config[:crit] }
      warning message if osd_hosts.any? { |host, metrics| metrics['percentage_out'] > config[:warn] }
    end
    ok
  end
end
