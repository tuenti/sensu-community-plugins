#! /usr/bin/env ruby
#
# check-ceph-mgr
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
#   Runs 'ceph status' command(s) to report health status of
#   MGR ceph daemons. May need read access to ceph keyring and/or root access
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

class CheckCephMGRHealth < Sensu::Plugin::Check::CLI
  option :user,
         description: 'Client name for authentication',
         short: '-u USER',
         long: '--user USER',
         proc: proc { |u| " --user #{u}" }

  option :monitor,
         description: 'Optional monitor IP',
         short: '-m MON',
         long: '--monitor MON',
         proc: proc { |m| " -m #{m}" }

  option :cluster,
         description: 'Optional cluster name',
         short: '-c NAME',
         long: '--cluster NAME',
         proc: proc { |c| " --cluster=#{c}" }

  option :timeout,
         description: 'Timeout (default 10)',
         short: '-t SEC',
         long: '--timeout SEC',
         proc: proc(&:to_i),
         default: 10

  option :active,
         short: '-a ACTIVE',
         long: '--active ACTIVE',
         description: 'Number of active MGR daemons. Critical if the current number of MGR daemons active is less than ACTIVE',
         proc: proc(&:to_i),
         default: 1

  option :warn,
         short: '-w WARN',
         long: '--warn WARN',
         description: 'Warn if the number of standby MGR daemons running are less than or equal to WARN',
         proc: proc(&:to_i),
         default: 2

  option :crit,
         short: '-c CRIT',
         long: '--critical CRIT',
         description: 'Critical if the number of standby MGR daemons running are less than or equal to CRIT',
         proc: proc(&:to_i),
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

  def run
    critical_message = ''
    warning_message = ''

    data = get_data('ceph status')
    standbys = data['mgrmap']['standbys'].length

    message_health = run_cmd('ceph health detail')

    if message_health.include? "no active mgr"
       critical_message += message_health
    end

    if standbys <= config[:crit]
      critical_message += "Number of MGR standbys is less than or equal to #{config[:crit]}\n"
    elsif standbys <= config[:warn]
      warning_message += "Number of MGR standbys is less than or equal to #{config[:warn]}\n"
    end

    if not data['mgrmap']['available']
      critical_message += "There is no available MGR daemon running\n"
    end

    if not critical_message.empty?
      critical critical_message
    elsif not warning_message.empty?
      warning warning_message
    end
    ok
  end
end
