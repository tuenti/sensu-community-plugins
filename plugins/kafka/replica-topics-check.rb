require 'sensu-plugin/check/cli'

class ReplicaTopicCheck < Sensu::Plugin::Check::CLI
	option :zookeeper,
		description: 'ZooKeeper connect string',
		short:       '-z NAME',
		long:        '--zookeeper NAME',
		default:     'kaf-01:2181'

	option :kafka_home,
		description: 'Kafka home',
		short:       '-k NAME',
		long:        '--kafka-home NAME',
		default:     '/opt/kafka'


	# read the output of a command
	# @param cmd [String] the command to read the output from
	def check_output(cmd)
		lines = 0;
		IO.popen(cmd + ' 2>&1') do |child|
			lines = child.readlines().size
		end

		return lines
	end

	def run
		kafka_topics_script = "#{config[:kafka_home]}/bin/kafka-topics.sh --zookeeper #{config[:zookeeper]} --describe"
		unknown "Can not find #{kafka_topics_script}" unless File.exist?(kafka_topics_script)	

		unavailable_partitions = check_output("#{kafka_topics_script} --unavailable-partitions")
		if unavailable_partitions > 0 then
			critical "There are #{unavailable_partitions} partitions unavailable"
			exit 2
		end

		under_replica_partitions = check_output("#{kafka_topics_script} --under-replicated-partitions")
		if under_replica_partitions > 0 then
			warning "There are #{under_replica_partitions} partitions not replicated (and probably unavailable)"
			exit 1
		end
	end
end