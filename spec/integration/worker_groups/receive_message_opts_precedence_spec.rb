# frozen_string_literal: true

# This spec tests which sqs_client_receive_message_opts entry a fetch uses, for
# a group loaded from a YAML config file.
#
# - A queue with its own entry uses only that entry; the group entry is not
#   merged into it
# - A queue without its own entry uses the group entry under the Symbol group
#   name the YAML load gives, not the String one
# - Every fetch asks for all attributes and message attributes, and for at most
#   10 messages, whatever the entry says

# EnvironmentLoader reads the config file through ERB, which only the CLI runner requires
require 'erb'
require 'tmpdir'

module ReceiveRecorder
  def receive_message(params = {}, options = {})
    DT[:receives] << params.merge(queue: params[:queue_url].split('/').last)
    super
  end
end

Aws::SQS::Client.prepend(ReceiveRecorder)

setup_sqs

QUEUE_OPTS_QUEUE = DT.queues[0]
GROUP_OPTS_QUEUE = DT.queues[1]
CAPPED_QUEUE = DT.queues[2]

[QUEUE_OPTS_QUEUE, GROUP_OPTS_QUEUE, CAPPED_QUEUE].each { |q| create_test_queue(q) }

class PrecedenceWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, _body)
    DT[:processed] << sqs_msg.queue_url.split('/').last
  end
end

[QUEUE_OPTS_QUEUE, GROUP_OPTS_QUEUE, CAPPED_QUEUE].each do |queue|
  Shoryuken.register_worker(queue, PrecedenceWorker)
end

Dir.mktmpdir do |dir|
  config_file = File.join(dir, 'shoryuken.yml')

  File.write(
    config_file,
    {
      'groups' => {
        'group1' => {
          'concurrency' => 25,
          'queues' => [QUEUE_OPTS_QUEUE, GROUP_OPTS_QUEUE, CAPPED_QUEUE]
        }
      }
    }.to_yaml
  )

  Shoryuken::EnvironmentLoader.setup_options(config_file: config_file).load
end

Shoryuken.sqs_client_receive_message_opts[:group1] = { wait_time_seconds: 1, max_number_of_messages: 1 }
Shoryuken.sqs_client_receive_message_opts['group1'] = { visibility_timeout: 7 }
Shoryuken.sqs_client_receive_message_opts[QUEUE_OPTS_QUEUE] = { visibility_timeout: 5 }
Shoryuken.sqs_client_receive_message_opts[CAPPED_QUEUE] = {
  max_number_of_messages: 25,
  attribute_names: %w[SentTimestamp],
  message_attribute_names: %w[custom]
}

[QUEUE_OPTS_QUEUE, GROUP_OPTS_QUEUE, CAPPED_QUEUE].each do |queue|
  Shoryuken::Client.queues(queue).send_message(message_body: 'msg')
end

poll_queues_until(timeout: 20) { DT[:processed].uniq.size >= 3 }

receives = DT[:receives].group_by { |params| params[:queue] }

[QUEUE_OPTS_QUEUE, GROUP_OPTS_QUEUE, CAPPED_QUEUE].each do |queue|
  assert(receives[queue].to_a.any?, "expected a receive_message call for #{queue}")

  receives[queue].each do |params|
    assert_equal(%w[All], params[:attribute_names])
    assert_equal(%w[All], params[:message_attribute_names])
  end
end

receives[QUEUE_OPTS_QUEUE].each do |params|
  assert_equal(5, params[:visibility_timeout])
  refute(params.key?(:wait_time_seconds), "the group entry must not be merged, got #{params}")
  assert(params[:max_number_of_messages] > 1, "the group entry must not be merged, got #{params}")
end

receives[GROUP_OPTS_QUEUE].each do |params|
  assert_equal(1, params[:wait_time_seconds])
  assert_equal(1, params[:max_number_of_messages])
  refute(params.key?(:visibility_timeout), "the 'group1' String entry must not be used, got #{params}")
end

receives[CAPPED_QUEUE].each do |params|
  assert_equal(10, params[:max_number_of_messages])
end

[QUEUE_OPTS_QUEUE, GROUP_OPTS_QUEUE, CAPPED_QUEUE].each { |q| delete_test_queue(q) }
