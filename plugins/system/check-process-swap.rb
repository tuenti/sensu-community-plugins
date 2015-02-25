#! /usr/bin/env ruby
#  encoding: UTF-8
#
#   check-process-swap.rb
#
# DESCRIPTION:
#   Check if a process is swapping
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
#   check-process-swap.rb -p PROCESS -f PID_FILE [-w]
#
#   PROCESS is used to look for the pids using "pidof PROCESS"
#   PID_FILE is used to look for the pid reading it for this file
#
#   It reports critical in case of the process is swapping, use -w
#   to report warning instead.
#
# NOTES:
#
# LICENSE:
#   Copyright 2015 Tuenti Technologies S.L. <sre@tuenti.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'

class CheckProcessSwap < Sensu::Plugin::Check::CLI
  option :process,
         short: '-p PROCESS',
         long: '--process PROCESS',
         description: 'Process name to check with pidof',
         default: nil

  option :pid_file,
         short: '-f PID_FILE',
         long: '--pid-file PID_FILE',
         description: 'File to look for the pids',
         default: nil

  def look_for_pids
    if config[:process] then
      `pidof #{config[:process]}`.split
    elsif config[:pid_file] then
      File.read(config[:pid_file]).split
    else
      []
    end
  end

  def is_swapping(pid)
    vm_swap = File.read("/proc/#{pid}/status").grep(/^VmSwap:/)[0].split[1].to_i
    vm_swap > 0
  end

  def run
    pids = look_for_pids
    warning "No processes found" if pids.empty?

    swapping_pids = pids.select { |pid| is_swapping(pid) }
    critical "Processes swapping: #{swapping_pids.join(', ')}" unless swapping_pids.empty?
    ok "No swap being used by #{pids.join(', ')}"
  end
end
