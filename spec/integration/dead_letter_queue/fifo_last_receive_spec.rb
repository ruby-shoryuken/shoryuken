# frozen_string_literal: true

# This spec tests Message#last_receive? on a FIFO queue with a redrive policy.
# Expected behavior: a failing message reports false on its first receive and true on the
# maxReceiveCount-th receive, then moves to the DLQ and the next message of its group runs.

setup_sqs

queue_name = "#{DT.uuid}.fifo"
dlq_name = "#{DT.uuid}.fifo"

create_queue_with_dlq(queue_name, dlq_name, max_receive_count: 2, attributes: { 'VisibilityTimeout' => '1' }, fifo: true)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

worker_class = Class.new do
  include Shoryuken::Worker

  def perform(sqs_msg, body)
    DT[:receives] << [body, sqs_msg.last_receive?]

    raise 'poison message' if body == 'poison'
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['batch'] = false
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

%w[poison next].each do |body|
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: body,
    message_group_id: 'group-a'
  )
end

poll_queues_until(timeout: 20) { DT[:receives].any? { |body, _| body == 'next' } }

assert_equal([['poison', false], ['poison', true], ['next', false]], DT[:receives])
assert_equal(1, queue_size(dlq_name))
