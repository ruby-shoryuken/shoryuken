# frozen_string_literal: true

# This spec tests `shoryuken sqs dump` and `shoryuken sqs mv` when SQS
# rejects the deletes from the source queue (here the queue is purged while
# the messages are in flight, so their receipt handles are no longer valid).
#
# Both commands print every rejected delete and exit with
# a non-zero status.
#
# Regression: both commands printed only the first rejected delete of a batch
# and exited with 0.

setup_sqs

def run_while_purging(source, *args)
  url = Shoryuken::Client.sqs.get_queue_url(queue_name: source).queue_url
  3.times { |i| Shoryuken::Client.sqs.send_message(queue_url: url, message_body: "message-#{i}") }

  command = Thread.new { run_shoryuken_sqs(*args) }

  Timeout.timeout(15) do
    sleep 0.1 until command.join(0) || Shoryuken::Client.sqs.get_queue_attributes(
      queue_url: url, attribute_names: %w[ApproximateNumberOfMessagesNotVisible]
    ).attributes['ApproximateNumberOfMessagesNotVisible'].to_i == 3
  end
  Shoryuken::Client.sqs.purge_queue(queue_url: url)

  command.value
end

# --- dump ---
with_queue_and_dir do |source, dir|
  status, output = run_while_purging(source, 'dump', source, '-p', dir)

  refute(status.success?, "dump must exit with a non-zero status, got: #{output}")
  assert_equal(3, output.scan(/Could not delete \S+, code: ReceiptHandleIsInvalid/).size, "got: #{output}")
  assert_includes(output, "[FAIL] Could not delete 3 dumped messages from #{source}", "got: #{output}")
end

# --- mv ---
with_queue_and_dir do |source, _dir|
  with_queue_and_dir do |target, _target_dir|
    status, output = run_while_purging(source, 'mv', source, target)

    refute(status.success?, "mv must exit with a non-zero status, got: #{output}")
    assert_equal(3, output.scan(/Could not delete \S+, code: ReceiptHandleIsInvalid/).size, "got: #{output}")
    assert_includes(output, "Moved 3 messages from #{source} to #{target}", "got: #{output}")
    assert_includes(output, "[FAIL] Could not delete 3 moved messages from #{source}", "got: #{output}")
    assert_equal(3, queue_size(target), 'the moved messages must be in the target')
  end
end
