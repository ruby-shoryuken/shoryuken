# frozen_string_literal: true

# This spec tests `shoryuken sqs mv` and `shoryuken sqs requeue` when a whole
# SQS request fails after the first batch went out (for mv a network error
# injected into the second `send_message_batch` or the first
# `delete_message_batch`, for requeue a dump file with the same message twice
# in its second batch).
#
# `mv` deletes each accepted batch from the source right after the send, makes
# the messages it did not move visible again in the source, prints a [FAIL]
# line with the counts and the error and exits with 1, so a re-run moves only
# the rest. After a failed delete it stops and names the moved messages it
# could not delete. `requeue` prints one [FAIL] line that names the lines it
# sent and the entries the queue rejected, and exits with 1. Neither prints a
# backtrace.
#
# Regression: both commands raised out with a backtrace; mv deleted nothing,
# so the sent messages stayed in flight in the source and a re-run sent them
# to the target again.

setup_sqs

BACKTRACE = /\.rb:\d+:in /

def injection_env(dir, method, call)
  path = File.join(dir, "fail_#{method}.rb")
  File.write(path, <<~RUBY)
    require 'aws-sdk-sqs'

    module FailRequest
      def #{method}(*)
        $calls = ($calls || 0) + 1
        raise Seahorse::Client::NetworkingError.new(Errno::ECONNRESET.new, 'injected') if $calls == #{call}

        super
      end
    end

    Aws::SQS::Client.prepend(FailRequest)
  RUBY
  { 'RUBYOPT' => "#{ENV.fetch('RUBYOPT', '')} -r#{path}" }
end

def send_bodies(queue, count)
  Array.new(count) { |i| format('message-%02d', i) }.each do |body|
    Shoryuken::Client.sqs.send_message(queue_url: queue_url(queue), message_body: body)
  end
end

def all_bodies(queue)
  bodies = []

  10.times do
    messages = Shoryuken::Client.sqs.receive_message(
      queue_url: queue_url(queue),
      max_number_of_messages: 10,
      wait_time_seconds: 1
    ).messages
    break if messages.empty?

    bodies.concat(messages.map(&:body))
  end

  bodies.sort
end

# --- mv ---
with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |source, dir|
  bodies = send_bodies(source, 25)

  with_queue_and_dir do |target, _target_dir|
    status, output = run_shoryuken_sqs('mv', source, target, env: injection_env(dir, 'send_message_batch', 2))

    assert_equal(1, status.exitstatus, "mv must exit with 1, got: #{output}")
    assert_includes(
      output,
      "[FAIL] Could not move 15 messages from #{source} to #{target}, they stay in #{source}: " \
      'injected (Seahorse::Client::NetworkingError). Moved 10 messages before the error',
      "got: #{output}"
    )
    refute(output.match?(BACKTRACE), "mv must not print a backtrace, got: #{output}")
    assert_equal(10, queue_size(target), 'the first batch must be in the target')
    assert_equal(
      { visible: 15, in_flight: 0 }, queue_counts(source),
      'the moved batch must be deleted from the source and the rest visible again'
    )

    status, output = run_shoryuken_sqs('mv', source, target)

    assert(status.success?, "a re-run of mv must succeed, got: #{output}")
    assert_includes(output, "Moved 15 messages from #{source} to #{target}", "got: #{output}")
    assert_equal(bodies, all_bodies(target), 'the target must hold every message once')
  end
end

# --- mv, rejected entries before the failed request ---
with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |source, dir|
  send_bodies(source, 25)

  # The FIFO target rejects every message, as none has a MessageGroupId
  with_queue_and_dir(fifo: true) do |target, _target_dir|
    status, output = run_shoryuken_sqs('mv', source, target, env: injection_env(dir, 'send_message_batch', 2))

    assert_equal(1, status.exitstatus, "mv must exit with 1, got: #{output}")
    assert_includes(
      output,
      "[FAIL] Could not move 15 messages from #{source} to #{target}, they stay in #{source}: " \
      'injected (Seahorse::Client::NetworkingError). Moved 0 messages before the error',
      "got: #{output}"
    )
    assert_includes(output, "[FAIL] Could not move 10 messages, they stay in #{source}", "got: #{output}")
    assert_equal(0, queue_size(target), 'the target must hold nothing')
    assert_equal({ visible: 25, in_flight: 0 }, queue_counts(source), 'every message must be visible again')
  end
end

# --- mv, failed delete request ---
with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |source, dir|
  send_bodies(source, 25)

  with_queue_and_dir do |target, _target_dir|
    status, output = run_shoryuken_sqs('mv', source, target, env: injection_env(dir, 'delete_message_batch', 1))

    assert_equal(1, status.exitstatus, "mv must exit with 1, got: #{output}")
    assert_includes(
      output,
      "[FAIL] Could not delete moved messages from #{source}: injected (Seahorse::Client::NetworkingError). " \
      "Stopped, 15 messages were not sent, they stay in #{source}. Moved 10 messages before the error",
      "got: #{output}"
    )
    assert_includes(output, "[FAIL] Could not delete 10 moved messages from #{source}", "got: #{output}")
    refute(output.match?(BACKTRACE), "mv must not print a backtrace, got: #{output}")
    assert_equal(10, queue_size(target), 'only the first batch must be sent')
    assert_equal(
      { visible: 15, in_flight: 10 }, queue_counts(source),
      'the unsent messages must be visible again, the undeleted ones stay in flight'
    )
  end
end

# --- requeue ---
with_queue_and_dir(fifo: true) do |target, dir|
  lines = Array.new(14) do |i|
    # The FIFO queue rejects lines 1 and 2, as they have no MessageGroupId
    attributes = i < 2 ? {} : { MessageGroupId: 'g' }
    JSON.dump(message_id: "id-#{i}", body: "message-#{i}", attributes: attributes, message_attributes: {})
  end
  # The second batch (lines 11-15) holds line 11 twice
  lines.insert(11, lines[10])
  path = File.join(dir, 'dump.jsonl')
  File.write(path, lines.join("\n"))

  status, output = run_shoryuken_sqs('requeue', target, path)

  assert_equal(1, status.exitstatus, "requeue must exit with 1, got: #{output}")
  assert_includes(
    output,
    "[FAIL] Could not requeue 7 messages from #{path} to #{target}: BatchEntryIdsNotDistinct " \
    "(Aws::SQS::Errors::BatchEntryIdsNotDistinct). Sent the first 10 lines of #{path} (8 requeued, 2 rejected), " \
    'resume from line 11',
    "got: #{output}"
  )
  refute(output.match?(BACKTRACE), "requeue must not print a backtrace, got: #{output}")
  assert_equal(8, queue_size(target), 'the accepted lines of the first batch must be in the target')
end
