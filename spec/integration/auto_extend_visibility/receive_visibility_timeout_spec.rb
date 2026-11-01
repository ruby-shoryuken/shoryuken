# frozen_string_literal: true

# This spec tests that auto_visibility_timeout extends a message by the
# visibility timeout set at receive time (sqs_client_receive_message_opts), not
# only by the queue's VisibilityTimeout attribute.
#
# The queue's VisibilityTimeout is 20s, but messages are received with a
# visibility_timeout of 6s, and the worker runs for 10s.
#
# The message is extended before its 6s visibility expires,
# so it is performed once and deleted.
#
# Regression: the extension was scheduled from the queue attribute (first one
# due after 15s), so the message became visible again after 6s and was
# performed again while the first perform still ran.

setup_sqs

DT.clear

queue_name = DT.uuid
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '20' })
Shoryuken.add_group('default', 2)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.sqs_client_receive_message_opts[queue_name] = { visibility_timeout: 6 }

receive_vt_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_visibility_timeout: true, auto_delete: true

  def perform(sqs_msg, _body)
    DT[:starts] << sqs_msg.attributes['ApproximateReceiveCount']
    sleep 10
    DT[:done] << sqs_msg.message_id
  end
end

receive_vt_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, receive_vt_worker)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'long running job')

# A short extra wait lets a redelivery that slipped in still show up
poll_queues_until(timeout: 30) { DT[:done].size >= 1 && sleep(2) }

assert_equal(1, DT[:starts].size, "the message must be performed once, got receive counts #{DT[:starts].to_a}")

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
attributes = Shoryuken::Client.sqs.get_queue_attributes(
  queue_url: queue_url,
  attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
).attributes
assert_equal(0, attributes.values.sum(&:to_i), "the message must be deleted, got #{attributes}")

delete_test_queue(queue_name)
