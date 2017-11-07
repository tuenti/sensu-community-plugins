#! /usr/bin/env ruby
#
# check-replica-topics
#
# DESCRIPTION:
#   This plugin checks replica topics properties.
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   ./check-replica-topics

require 'sensu-plugin/check/cli'

class ReplicaTopicCheck < Sensu::Plugin::Check::CLI
    option :zookeeper,
        description: 'ZooKeeper connect string',
        short:       '-z NAME',
        long:        '--zookeeper NAME',
        default:     'localhost:2181'

    option :kafka_home,
        description: 'Kafka home',
        short:       '-k NAME',
        long:        '--kafka-home NAME',
        default:     '/opt/kafka'

    # gets the number of rows returned by the command
    # @param cmd [String] the command to read the output from
    def check_output(cmd)
        lines = 0;
        IO.popen(cmd + ' 2>&1') do |child|
            lines = child.readlines().size
        end

        return lines
    end

    def run
        kafka_topics_script = "#{config[:kafka_home]}/bin/kafka-topics.sh"
        unknown "Can not find #{kafka_topics_script}" unless File.exist?(kafka_topics_script)
        kafka_cmd = "#{kafka_topics_script} --zookeeper #{config[:zookeeper]} --describe"

        unavailable_partitions = check_output("#{kafka_cmd} --unavailable-partitions")
        critical "There are #{unavailable_partitions} partitions unavailable" if unavailable_partitions > 0

        under_replica_partitions = check_output("#{kafka_cmd} --under-replicated-partitions")
        warning "There are #{under_replica_partitions} partitions not replicated (and probably unavailable)" if under_replica_partitions > 0

        ok if unavailable_partitions == 0 && under_replica_partitions == 0
    end
end