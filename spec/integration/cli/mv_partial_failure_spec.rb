# frozen_string_literal: true

# This spec tests `shoryuken sqs mv` and `shoryuken sqs requeue` when the
# target queue rejects some entries of a batch (here a FIFO queue that rejects
# messages without a MessageGroupId).
#
# Expected behavior: mv deletes from the source only the messages the target
# accepted, so the rejected ones stay in the source. Both commands print every
# rejected entry, count only the accepted messages in their success line, and
# exit with a non-zero status. A requeue with no rejected entry exits with 0.
#
# Regression: mv deleted every received message, so the rejected ones were
# lost; both commands printed only the first rejected entry of a batch and
# exited with 0, reporting all messages as moved or requeued.

setup_sqs

def with_fifo_queue
  queue = "#{DT.uuid}.fifo"
  create_fifo_queue(queue)

  yield queue
ensure
  delete_test_queue(queue) if queue
end

def bodies(queue)
  url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url

  Shoryuken::Client.sqs.receive_message(queue_url: url, max_number_of_messages: 10).messages.map(&:body).sort
end

def write_dump(dir, name, messages)
  path = File.join(dir, name)
  lines = messages.map do |body, group|
    attributes = group ? { MessageGroupId: group } : {}
    JSON.dump(message_id: DT.uuid, body: body, attributes: attributes, message_attributes: {})
  end
  File.write(path, lines.join("\n"))
  path
end

grouped = %w[grouped-1 grouped-2]
plain = %w[plain-1 plain-2 plain-3]

# --- mv ---
with_queue_and_dir do |source, _dir|
  url = Shoryuken::Client.sqs.get_queue_url(queue_name: source).queue_url
  grouped.each { |body| Shoryuken::Client.sqs.send_message(queue_url: url, message_body: body, message_group_id: 'g') }
  plain.each { |body| Shoryuken::Client.sqs.send_message(queue_url: url, message_body: body) }

  with_fifo_queue do |target|
    status, output = run_shoryuken_sqs('mv', source, target)

    refute(status.success?, "mv must exit with a non-zero status, got: #{output}")
    assert_equal(
      3, output.scan(/Could not requeue \S+, code: MissingParameter/).size,
      "every rejected entry must be printed, got: #{output}"
    )
    assert_includes(output, "Moved 2 messages from #{source} to #{target}", "got: #{output}")
    assert_includes(output, "[FAIL] Could not move 3 messages, they stay in #{source}", "got: #{output}")
    assert_equal(grouped, bodies(target), 'the target must hold only the accepted messages')
    assert_equal(3, queue_size(source), 'the rejected messages must stay in the source')
  end
end

# --- requeue ---
with_queue_and_dir do |_queue, dir|
  with_fifo_queue do |target|
    path = write_dump(dir, 'accepted.jsonl', grouped.map { |body| [body, 'g'] })
    status, output = run_shoryuken_sqs('requeue', target, path)

    assert(status.success?, "requeue with no rejected entry must exit with 0, got: #{output}")
    assert_includes(output, "Requeued 2 messages from #{path} to #{target}", "got: #{output}")
  end

  with_fifo_queue do |target|
    path = write_dump(dir, 'mixed.jsonl', grouped.map { |body| [body, 'g'] } + plain.map { |body| [body, nil] })
    status, output = run_shoryuken_sqs('requeue', target, path)

    refute(status.success?, "requeue must exit with a non-zero status, got: #{output}")
    assert_equal(
      3, output.scan(/Could not requeue \S+, code: MissingParameter/).size,
      "every rejected entry must be printed, got: #{output}"
    )
    assert_includes(output, "Requeued 2 messages from #{path} to #{target}", "got: #{output}")
    assert_includes(output, "[FAIL] Could not requeue 3 messages from #{path} to #{target}", "got: #{output}")
    assert_equal(2, queue_size(target), 'the target must hold only the accepted messages')
  end
end
