# frozen_string_literal: true

# This spec tests `shoryuken sqs dump` followed by `shoryuken sqs requeue` of
# the dump file into the same FIFO queue, within the 5-minute deduplication
# window of SQS.
#
# Expected behavior: requeue sends each message with a new deduplication id,
# so every message is delivered again, in order, with its message group id.
#
# Regression: requeue sent the original deduplication ids, so SQS accepted
# the messages but did not deliver them: requeue reported success and the
# queue stayed empty.

setup_sqs

with_queue_and_dir(fifo: true) do |queue, dir|
  url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  bodies = Array.new(4) { |i| "message-#{i}" }
  bodies.each_with_index do |body, i|
    Shoryuken::Client.sqs.send_message(
      queue_url: url, message_body: body, message_group_id: 'g1', message_deduplication_id: "d-#{i}"
    )
  end

  status, output = run_shoryuken_sqs('dump', queue, '-p', dir)
  assert(status.success?, "dump must succeed, got: #{output}")
  assert_equal(0, queue_size(queue), 'dump must delete the messages')

  path = Dir[File.join(dir, '*.jsonl')].first
  status, output = run_shoryuken_sqs('requeue', queue, path)
  assert(status.success?, "requeue must succeed, got: #{output}")

  messages = Shoryuken::Client.sqs.receive_message(
    queue_url: url, max_number_of_messages: 10, attribute_names: ['MessageGroupId'], wait_time_seconds: 1
  ).messages

  assert_equal(bodies, messages.map(&:body), 'every requeued message must be delivered, in order')
  assert_equal(%w[g1], messages.map { |m| m.attributes['MessageGroupId'] }.uniq, 'the group id must be kept')
end
