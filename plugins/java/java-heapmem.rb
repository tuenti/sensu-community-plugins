#! /usr/bin/env ruby
#
#  java-heapmem
#
# DESCRIPTION:
#   Java HeapMem Check
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
#   #YELLOW
#
# NOTES:
#
# LICENSE:
#   Copyright 2011 Sonian, Inc <chefs@sonian.net>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'English'

class CheckJavaHeapMem < Sensu::Plugin::Check::CLI
  check_name 'Java HeapMem'

  option :warn, short: '-w WARNLEVEL', default: '85'
  option :crit, short: '-c CRITLEVEL', default: '95'

  def run
    warn_procs = []
    crit_procs = []
    java_pids = []

    IO.popen('jps -q') do |cmd|
      java_pids = cmd.read.split
    end

    java_pids.each do |java_proc|
      hmx = nil
      hmu = nil
      IO.popen("jstat -gccapacity #{java_proc} 1 1 2>&1 | tail -n 1") do |cmd|
	pout = cmd.read.split
        hmx = pout[1].to_f + pout[7].to_f
      end
      exit_code = $CHILD_STATUS.exitstatus
      next if exit_code != 0

      IO.popen("jstat -gc #{java_proc} 1 1 2>&1 | tail -n 1") do |cmd|
	pout = cmd.read.split
        hmu = pout[2].to_f + pout[3].to_f + pout[5].to_f + pout[7].to_f + pout[9].to_f
      end
      exit_code = $CHILD_STATUS.exitstatus
      next if exit_code != 0

      proc_heap = ((hmu.to_f * 100) / hmx.to_f).round(1)
      warn_procs << java_proc if proc_heap > config[:warn].to_f
      crit_procs << java_proc if proc_heap > config[:crit].to_f
    end

    if !crit_procs.empty?
      critical "Java processes Over HeapMem CRIT threshold of #{config[:crit]}%: #{crit_procs.join(', ')}"
    elsif !warn_procs.empty?
      warning "Java processes Over HeapMem WARN threshold of #{config[:warn]}%: #{warn_procs.join(', ')}"
    else
      ok 'No Java processes over HeapMem thresholds'
    end
  end
end
