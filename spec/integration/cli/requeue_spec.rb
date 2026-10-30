# frozen_string_literal: true

# This spec tests `shoryuken sqs dump` followed by `shoryuken sqs requeue` of
# the dump file into the queue, on a standard queue and on a FIFO queue.
#
# Expected behavior: requeue sends every dumped message back with its body and
# its String and Number message attributes. On a FIFO queue it also keeps each
# message's group id and the order within each group.
#
# Regression: #470 - requeue did not pass MessageGroupId, so SQS rejected the
# send to a FIFO queue and requeue failed.

setup_sqs

ATTRIBUTES = {
  'text' => { data_type: 'String', string_value: 'value' },
  'count' => { data_type: 'Number', string_value: '42' },
  'kind' => { data_type: 'String.custom', string_value: 'custom' }
}.freeze

def queue_url(queue)
  Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
end

def receive_all(queue, count)
  messages = []

  10.times do
    break if messages.size >= count

    messages.concat(
      Shoryuken::Client.sqs.receive_message(
        queue_url: queue_url(queue),
        max_number_of_messages: 10,
        attribute_names: ['MessageGroupId'],
        message_attribute_names: ['All'],
        wait_time_seconds: 1
      ).messages
    )
  end

  messages
end

def dump_and_requeue(queue, dir, count)
  status, output = run_shoryuken_sqs('dump', queue, '-p', dir)
  assert(status.success?, "dump must succeed, got: #{output}")
  assert_equal(0, queue_size(queue), 'dump must delete the messages')

  status, output = run_shoryuken_sqs('requeue', queue, Dir[File.join(dir, '*.jsonl')].first)
  assert(status.success?, "requeue must succeed, got: #{output}")
  assert_includes(output, "Requeued #{count} messages")
end

def assert_attributes(message)
  ATTRIBUTES.each do |name, value|
    attribute = message.message_attributes[name]

    assert_equal(value[:data_type], attribute&.data_type, "#{name} must keep its data type")
    assert_equal(value[:string_value], attribute&.string_value, "#{name} must keep its value")
  end
end

# --- standard queue ---
with_queue_and_dir do |queue, dir|
  bodies = Array.new(3) { |i| "standard-#{i}" }

  bodies.each do |body|
    Shoryuken::Client.sqs.send_message(queue_url: queue_url(queue), message_body: body, message_attributes: ATTRIBUTES)
  end

  dump_and_requeue(queue, dir, bodies.size)

  messages = receive_all(queue, bodies.size)
  assert_equal(bodies, messages.map(&:body).sort, 'every message must be requeued with its body')
  messages.each { |message| assert_attributes(message) }
end

# --- FIFO queue ---
with_queue_and_dir(fifo: true) do |queue, dir|
  sent = [%w[g1 a-0], %w[g2 b-0], %w[g1 a-1], %w[g2 b-1], %w[g1 a-2]]

  sent.each do |group, body|
    Shoryuken::Client.sqs.send_message(
      queue_url: queue_url(queue),
      message_body: body,
      message_group_id: group,
      message_attributes: ATTRIBUTES
    )
  end

  dump_and_requeue(queue, dir, sent.size)

  messages = receive_all(queue, sent.size)
  assert_equal(sent.size, messages.size, "every message must be requeued, got: #{messages.map(&:body)}")

  %w[g1 g2].each do |group|
    expected = sent.select { |g, _| g == group }.map(&:last)
    received = messages.select { |m| m.attributes['MessageGroupId'] == group }.map(&:body)

    assert_equal(expected, received, "#{group} must keep its messages in order")
  end

  messages.each { |message| assert_attributes(message) }
end
