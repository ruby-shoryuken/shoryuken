# frozen_string_literal: true

# This spec tests `shoryuken sqs mv` and `shoryuken sqs requeue` with messages
# so large that a batch of 10 is over the SQS batch payload limit
# (`MAX_BATCH_SIZE`, 1 MiB).
#
# Expected behavior: both commands split the messages into batches under the
# limit, so every message reaches the target and the command exits with 0.
#
# Regression: #663. The commands sent up to 10 messages per batch whatever
# their size, so SQS rejected the batch with BatchRequestTooLong and the
# messages were not moved or requeued.

setup_sqs

def queue_url(queue)
  Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
end

def received_bodies(queue)
  Shoryuken::Client.sqs.receive_message(
    queue_url: queue_url(queue), max_number_of_messages: 10, wait_time_seconds: 1
  ).messages.map(&:body).sort
end

# Two messages fit in a batch, three do not
bodies = Array.new(5) { |i| "#{i}-#{'b' * 400_000}" }

# --- mv ---
with_queue_and_dir do |source, _dir|
  bodies.each { |body| Shoryuken::Client.sqs.send_message(queue_url: queue_url(source), message_body: body) }

  with_queue_and_dir do |target, _target_dir|
    status, output = run_shoryuken_sqs('mv', source, target)

    assert(status.success?, "mv must succeed, got: #{output[0, 2000]}")
    assert_includes(output, "Moved 5 messages from #{source} to #{target}", "got: #{output[0, 2000]}")
    assert_equal(0, queue_size(source), 'the moved messages must be deleted from the source')
    assert_equal(bodies, received_bodies(target), 'every message must reach the target')
  end
end

# --- requeue ---
with_queue_and_dir do |target, dir|
  path = File.join(dir, 'large.jsonl')
  lines = bodies.map { |body| JSON.dump(message_id: DT.uuid, body: body, attributes: {}, message_attributes: {}) }
  File.write(path, lines.join("\n"))

  status, output = run_shoryuken_sqs('requeue', target, path)

  assert(status.success?, "requeue must succeed, got: #{output[0, 2000]}")
  assert_includes(output, "Requeued 5 messages from #{path} to #{target}", "got: #{output[0, 2000]}")
  assert_equal(bodies, received_bodies(target), 'every message must reach the target')
end
