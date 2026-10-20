# frozen_string_literal: true

# This spec tests `shoryuken sqs requeue` and `shoryuken sqs mv` sending FIFO
# messages to a queue that saw their deduplication ids within the 5-minute
# deduplication window of SQS: a dump requeued into the same queue, and a move
# back to the queue the messages came from (e.g. a FIFO DLQ redrive).
#
# Expected behavior: both commands send each message with a new deduplication
# id, so every message is delivered again, in order, with its message group id.
#
# Regression: both commands sent the original deduplication ids, so SQS
# accepted the messages but did not deliver them: the commands reported
# success and the messages were lost.

setup_sqs

def send_fifo_messages(queue, bodies)
  url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  bodies.each_with_index do |body, i|
    Shoryuken::Client.sqs.send_message(
      queue_url: url, message_body: body, message_group_id: 'g1', message_deduplication_id: "d-#{i}"
    )
  end
end

def assert_delivered(queue, bodies)
  url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  messages = Shoryuken::Client.sqs.receive_message(
    queue_url: url, max_number_of_messages: 10, attribute_names: ['MessageGroupId'], wait_time_seconds: 1
  ).messages

  assert_equal(bodies, messages.map(&:body), 'every message must be delivered, in order')
  assert_equal(%w[g1], messages.map { |m| m.attributes['MessageGroupId'] }.uniq, 'the group id must be kept')
end

bodies = Array.new(4) { |i| "message-#{i}" }

# --- requeue ---
with_queue_and_dir(fifo: true) do |queue, dir|
  send_fifo_messages(queue, bodies)

  status, output = run_shoryuken_sqs('dump', queue, '-p', dir)
  assert(status.success?, "dump must succeed, got: #{output}")
  assert_equal(0, queue_size(queue), 'dump must delete the messages')

  status, output = run_shoryuken_sqs('requeue', queue, Dir[File.join(dir, '*.jsonl')].first)
  assert(status.success?, "requeue must succeed, got: #{output}")

  assert_delivered(queue, bodies)
end

# --- mv ---
with_queue_and_dir(fifo: true) do |source, _dir|
  with_queue_and_dir(fifo: true) do |target, _target_dir|
    send_fifo_messages(source, bodies)

    status, output = run_shoryuken_sqs('mv', source, target)
    assert(status.success?, "mv must succeed, got: #{output}")

    status, output = run_shoryuken_sqs('mv', target, source)
    assert(status.success?, "mv back must succeed, got: #{output}")
    assert_equal(0, queue_size(target), 'mv must delete the messages from the target')

    assert_delivered(source, bodies)
  end
end
