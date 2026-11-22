# frozen_string_literal: true

# This spec tests which sqs_client_receive_message_opts entry a fetch uses, for
# a group loaded from a YAML config file (`-C`).
#
# - A queue with its own entry uses only that entry; the group entry is not
#   merged into it
# - A queue without its own entry uses the group entry under the Symbol group
#   name the YAML load gives, not the String one
# - Every fetch asks for all attributes and message attributes, and for at most
#   10 messages, whatever the entry says

setup_sqs

def expect_receive_options(dir, queue_opts_queue, group_opts_queue, capped_queue)
  queues = [queue_opts_queue, group_opts_queue, capped_queue]
  receives = File.join(dir, 'receives')
  processed = File.join(dir, 'processed')
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    require 'json'

    module ReceiveRecorder
      def receive_message(params = {}, options = {})
        File.write('#{receives}', "\#{JSON.generate(params)}\\n", mode: 'a')
        super
      end
    end

    Aws::SQS::Client.prepend(ReceiveRecorder)

    Shoryuken.sqs_client_receive_message_opts[:group1] = { wait_time_seconds: 1, max_number_of_messages: 1 }
    Shoryuken.sqs_client_receive_message_opts['group1'] = { visibility_timeout: 7 }
    Shoryuken.sqs_client_receive_message_opts['#{queue_opts_queue}'] = { visibility_timeout: 5 }
    Shoryuken.sqs_client_receive_message_opts['#{capped_queue}'] = {
      max_number_of_messages: 25,
      attribute_names: %w[SentTimestamp],
      message_attribute_names: %w[custom]
    }

    class PrecedenceWorker
      include Shoryuken::Worker

      shoryuken_options auto_delete: true, batch: false

      def perform(sqs_msg, _body)
        File.write('#{processed}', "\#{sqs_msg.queue_url.split('/').last}\\n", mode: 'a')
      end
    end

    #{queues.inspect}.each { |queue| Shoryuken.register_worker(queue, PrecedenceWorker) }
  RUBY

  config_file = File.join(dir, 'shoryuken.yml')
  File.write(config_file, <<~YAML)
    groups:
      group1:
        concurrency: 25
        queues:
          - #{queue_opts_queue}
          - #{group_opts_queue}
          - #{capped_queue}
  YAML

  queues.each { |queue| Shoryuken::Client.queues(queue).send_message(message_body: 'msg') }

  status, output = run_shoryuken_until('-r', boot_file, '-C', config_file) do
    File.exist?(processed) && File.readlines(processed).uniq.size >= 3
  end

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")

  calls = File.readlines(receives).map { |line| JSON.parse(line) }.group_by { |params| params['queue_url'].split('/').last }

  queues.each do |queue|
    assert(calls[queue].to_a.any?, "expected a receive_message call for #{queue}")

    calls[queue].each do |params|
      assert_equal(%w[All], params['attribute_names'])
      assert_equal(%w[All], params['message_attribute_names'])
    end
  end

  calls[queue_opts_queue].each do |params|
    assert_equal(5, params['visibility_timeout'])
    refute(params.key?('wait_time_seconds'), "the group entry must not be merged, got #{params}")
    assert(params['max_number_of_messages'] > 1, "the group entry must not be merged, got #{params}")
  end

  calls[group_opts_queue].each do |params|
    assert_equal(1, params['wait_time_seconds'])
    assert_equal(1, params['max_number_of_messages'])
    refute(params.key?('visibility_timeout'), "the 'group1' String entry must not be used, got #{params}")
  end

  calls[capped_queue].each do |params|
    assert_equal(10, params['max_number_of_messages'])
  end
end

with_queue_and_dir do |queue_opts_queue, dir|
  with_queue_and_dir do |group_opts_queue, _|
    with_queue_and_dir do |capped_queue, _|
      expect_receive_options(dir, queue_opts_queue, group_opts_queue, capped_queue)
    end
  end
end
