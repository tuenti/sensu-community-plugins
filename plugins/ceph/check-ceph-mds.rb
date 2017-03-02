#! /usr/bin/env ruby
#
# check-ceph-mds
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
#   Runs 'ceph mds stat' command(s) to report health status of
#   MDS ceph daemons. May need read access to ceph keyring and/or root access
#   for authentication.
#
#   Using -u (--user) option allows to set the username to connect with
#   the ceph cluster. By default the user is admin.
#
#   Using -c (--cluster) option allows to set the cluster name to connect with
#   the ceph cluster. By default the user is ceph.
#
#   Using -m (--monitor) option allows to set an option monitor IP address to
#   connect with the ceph cluster.
#
#   Using -t (--timeout) option allows to set the timeout in seconds to
#   execute the ceph commands. By default the timeout is 10 seconds.
#
#   Using --show_stderr option allows to be considered the standard error
#   output when executing the check. By default this option is false.
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

class CheckCephMDSHealth < Sensu::Plugin::Check::CLI
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

  option :warn,
         short: '-w WARN',
         long: '--warn WARN',
         description: 'Warn if the number of MDS daemons running are less than WARN',
         proc: proc(&:to_f),
         default: 2

  option :crit,
         short: '-c',
         long: '--critical CRIT',
         description: 'Critical if the number of MDS daemons running are less than CRIT',
         proc: proc(&:to_f),
         default: 1

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
    data = get_data('ceph mds stat')
    filesystems = data['fsmap']['filesystems']
  end

  def run
    critical_message = ''
    warning_message = ''

    filesystems = general_stats()

    message = run_cmd('ceph mds stat')

    filesystems.each do |filesystem|
      base_message = "Filesystem #{filesystem['mdsmap']['fs_name']} ID=#{filesystem['id']}"
      fs_in = filesystem['mdsmap']['in'].length
      fs_up = filesystem['mdsmap']['up'].length
      fs_failed = filesystem['mdsmap']['failed'].length
      fs_damaged = filesystem['mdsmap']['damaged'].length
      fs_stopped = filesystem['mdsmap']['stopped'].length
      gids = filesystem['mdsmap']['info']
      gids.any? { |gid, data| not data['state'].start_with?('up:') }

      critical_message += "#{base_message} failed\n" if fs_failed > 0
      critical_message += "#{base_message} damaged\n" if fs_damaged > 0
      critical_message += "#{base_message} stopped\n" if fs_stopped > 0

      critical_message += "#{base_message} not enough MDS daemons running\n" if gids.length <= config[:crit]
      warning_message  += "#{base_message} not enougth standby MDS daemons running\n" if gids.length <= config[:warn]
    end

    if not critical_message.empty?
      critical critical_message + message
    elsif not warning_message.empty?
      warning warning_message + message
    end
    ok
  end
end
