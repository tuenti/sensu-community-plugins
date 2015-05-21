#!/usr/bin/env ruby
#
# Check the size of the queue of an instance of postfix
# ===
#
# Copyright (c) 2015, Tuenti SRE Team <sre@tuenti.com>
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'

class PostfixQueueLength < Sensu::Plugin::Check::CLI
  option :configuration,
         short: '-p CONFIGURATION_PATH',
         long: '--path CONFIGURATION_PATH',
         description: 'Path to the postfix instance configuration',
         default: '/etc/postfix'

  option :queues,
         short: '-q QUEUES',
         long: '--queues QUEUES',
         description: 'Comma-separated list of queue lists',
         default: 'deferred,active,maildrop'


  option :warning,
         short: '-w WARN_NUM',
         long: '--warnnum WARN_NUM',
         description: 'Number of messages in the queue considered to be a warning',
         default: 600

  option :critical,
         short: '-c CRIT_NUM',
         long: '--critnum CRIT_NUM',
         description: 'Number of messages in the queue considered to be critical',
         default: 600

  def run
    spooling_path = `/usr/sbin/postconf -c #{config[:configuration]} queue_directory`.split[-1]
    queue_length = 0

    config[:queues].split(',').each do |queue|
      queue_spooling_path = File.join(spooling_path, queue)
      unknown "Couldn't read #{queue_spooling_path}, you may need sudo" unless File.directory? queue_spooling_path
      queue_length += `find #{queue_spooling_path} -type f | wc -l`.to_i
    end

    message = "#{queue_length} messages in the #{config[:queues]} queues for instance #{config[:configuration]}"

    critical message if queue_length >= config[:critical].to_i
    warning message if queue_length >= config[:warning].to_i
    ok message
  end
end
