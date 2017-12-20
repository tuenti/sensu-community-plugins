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
require 'zookeeper'
require 'socket'
require 'json'

class ReplicaTopicCheck < Sensu::Plugin::Check::CLI
    option :zookeeper,
        description: 'Zookeeper connect string',
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
    def get_misbehaving_nodes(cmd)
        missing_leaders = Array.new
        IO.popen(cmd + ' 2>&1') do |child|
            lines = child.readlines()
            lines.each() do |line|
                leader = line.gsub!(/[\t ]*Topic:[\t ]*([a-zA-Z0-9\-\_]+)[\t ]*Partition:[\t ]*([0-9]+)[\t ]*Leader:[\t ]*([0-9]+)[\t ]*Replicas:[\t ]*([0-9,]+)[\t ]*Isr:[\t ]*([0-9,]+).*/, '\3')
                if leader != nil
                    missing_leaders.push(leader.strip())
                end
            end
        end

        return missing_leaders
    end

    def run
        zk = Zookeeper.new(config[:zookeeper])
        kafka_id = ''
        hostname = Socket.gethostname

        zk.get_children(path:'/brokers/ids')[:children].each { |id|
            broker_info = zk.get(path:"/brokers/ids/#{id}")[:data]
            json = JSON.parse(broker_info)

            if json["host"].include? hostname 
                kafka_id = id
            end
        }

        kafka_topics_script = "#{config[:kafka_home]}/bin/kafka-topics.sh"
        unknown "Can not find #{kafka_topics_script}" unless File.exist?(kafka_topics_script)
        kafka_cmd = "#{kafka_topics_script} --zookeeper #{config[:zookeeper]} --describe"

        missing_leaders = get_misbehaving_nodes("#{kafka_cmd} --unavailable-partitions")
        missing_leaders.concat(get_misbehaving_nodes("#{kafka_cmd} --under-replicated-partitions"))
        critical "There are problems with leader #{hostname}. It's leader of a partition under-replicated / unavailable" if missing_leaders.include? kafka_id

        ok unless missing_leaders.include? kafka_id
    end
end