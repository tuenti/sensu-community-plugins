#!/usr/bin/env ruby
#
#   check-open-files
#
# DESCRIPTION:
#   Count open files and alerts if a threshold is overrun.
#   If a process is indicated, it counts the open files of this process, if
#   not, it reports over the syste-wide open files.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#
# NOTES:
#
# LICENSE:
#   Copyright 2015 Tuenti Technologies S.L. <sre@tuenti.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'

class CheckOpenFiles < Sensu::Plugin::Check::CLI
  option :warn,
         short: '-w WARN',
         long: '--warn WARN',
         proc: proc(&:to_i),
         description: 'Open files count WARNING threshold'

  option :crit,
         short: '-c CRIT',
         long: '--crit CRIT',
         proc: proc(&:to_i),
         description: 'Open files count CRITICAL threshold'

  option :pidfile,
         short: '-f PIDFILE',
         long: '--pid-file',
         description: 'Pid file of the process to count open files of, needs read access to the pid file'

  option :process,
         short: '-p PROCESS',
         long: '--process PROCESS',
         description: 'Process name to count open files of, using pidof for lookup, needs sudo permissions for /usr/bin/lsof'
         

  def process_open_files(pid)
    `sudo /usr/bin/lsof -p #{pid}`.split("\n").count - 1
  end

  def run
    open_files = if config[:pidfile]
      process_open_files File.read(config[:pidfile])
    elsif config[:process]
      process_open_files `pidof #{config[:process]}`
    else
      `cat /proc/sys/fs/file-nr`.split[0].to_i
    end

    message = "Open files: #{open_files}"
    critical message if config[:crit] and open_files > config[:crit]
    warning message if config[:warn] and open_files > config[:warn]
    ok message
  end
end

