#! /usr/bin/env ruby
#  encoding: UTF-8
#
#   check-sentinels-can-decide
#
# DESCRIPTION:
#   Asks a redis sentinel if it thinks that its cluster can reach quorum
#   and a majority to take decissions, or if it's in risk of losing this
#   capabilities if some other node dies.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   redis
#   gem: sensu-plugin
#
# USAGE:
#   check-sentinels-can-decide.rb -h HOST -p PORT -m MASTER_NAME -w WARNING_EDGE -c CRITICAL_EDGE
#
#   The edge is estimated as the margin of nodes that can go down before the
#   cluster loses the capacity of decission.
#
#   WARNING_EDGE defaults to 1
#   CRITICAL_EDGE defaults to 0
#
# NOTES:
#
# LICENSE:
#   Copyright 2014 Tuenti Technologies S.L. <sre@tuenti.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'

class CheckSentinelsCanDecide < Sensu::Plugin::Check::CLI
  option :host,
         short: '-h HOST',
         long: '--host HOST',
         description: 'Host where the sentinel is running',
         default: '127.0.0.1'

  option :port,
         short: '-p PORT',
         long: '--port PORT',
         description: 'Port where sentinel is listening',
         default: 26379

  option :master_name,
         short: '-m MASTER_NAME',
         long: '--master_name MASTER_NAME',
         description: 'Host where the sentinel is running'

  option :warning,
         short: '-w WARN',
         proc: proc(&:to_i),
         default: 1

  option :critical,
         short: '-c CRIT',
         proc: proc(&:to_i),
         default: 0

  def redis_cli_command
    "redis-cli -h #{config[:host]} -p #{config[:port]} --raw"
  end

  def sentinels_info
    command = "#{redis_cli_command} sentinel sentinels #{config[:master_name]}"
    IO.popen(command)
  end

  def quorum
    command = "#{redis_cli_command} sentinel master #{config[:master_name]} | grep -A1 quorum | tail -1"
    `#{command}`.strip.to_i
  end

  def run
    total_sentinels = 1 # Count itself first
    down_sentinels = 0
    sentinels_info.each do |line|
      total_sentinels += 1 if line.strip == 'name'
      down_sentinels += 1 unless line.index('down,sentinel').nil?
    end

    alive_sentinels = total_sentinels - down_sentinels
    majority = total_sentinels / 2 + 1
    majority_edge = alive_sentinels - majority

    number_message = "#{alive_sentinels} of #{total_sentinels} alive sentinels"
    critical "#{number_message}, quorum of #{quorum} cannot be reach" if alive_sentinels < quorum
    critical "#{number_message}, majority cannot be reach" if majority_edge < config[:critical]
    warning  "#{number_message}, too few sentinels in cluster" if majority_edge < config[:warning]
    ok number_message
  end
end
