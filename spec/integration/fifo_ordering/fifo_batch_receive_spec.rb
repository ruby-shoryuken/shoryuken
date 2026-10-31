# frozen_string_literal: true

# This spec tests batch receive on a FIFO queue.
# Expected behavior: a worker with batch: true receives up to 10 messages per
# receive (the one-message FIFO cap applies only to non-batch workers), and the
# messages of each message group arrive in send order across all batches.

setup_sqs

queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: true

  def perform(sqs_msgs, _bodies)
    DT[:batch_sizes] << sqs_msgs.size
    sqs_msgs.each { |msg| DT[msg.attributes['MessageGroupId']] << msg.body }
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

groups = %w[group-a group-b]
expected = groups.to_h { |group| [group, (0..7).map { |i| "#{group}-#{i}" }] }

8.times do |i|
  groups.each do |group|
    Shoryuken::Client.sqs.send_message(
      queue_url: queue_url,
      message_body: expected[group][i],
      message_group_id: group,
      message_deduplication_id: SecureRandom.uuid
    )
  end
end

sleep 1

poll_queues_until { DT[:batch_sizes].sum >= 16 }

assert_equal(16, DT[:batch_sizes].sum)
assert(DT[:batch_sizes].all? { |size| size <= 10 }, "Expected batches of at most 10, got #{DT[:batch_sizes]}")
assert_equal(10, DT[:batch_sizes].first)
groups.each { |group| assert_equal(expected[group], DT[group]) }
