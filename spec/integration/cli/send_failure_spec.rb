# frozen_string_literal: true

# This spec tests `shoryuken sqs mv` and `shoryuken sqs requeue` when a whole
# `send_message_batch` request fails after the first batch went out (for mv a
# network error injected into the second request, for requeue a dump file
# with the same message twice in its second batch).
#
# `mv` deletes each accepted batch from the source right after the send, makes
# the messages it did not move visible again in the source, prints one
# [FAIL] line with the counts and the error and exits with 1, so a re-run
# moves only the rest. `requeue` prints one [FAIL] line that names the lines
# it sent, and exits with 1. Neither prints a backtrace.
#
# Regression: both commands raised out with a backtrace; mv deleted nothing,
# so the sent messages stayed in flight in the source and a re-run sent them
# to the target again.

setup_sqs

BACKTRACE = /\.rb:\d+:in /

def write_injection(dir)
  path = File.join(dir, 'fail_second_send.rb')
  File.write(path, <<~RUBY)
    require 'aws-sdk-sqs'

    module FailSecondSend
      def send_message_batch(*)
        $send_calls = ($send_calls || 0) + 1
        raise Seahorse::Client::NetworkingError.new(Errno::ECONNRESET.new, 'injected') if $send_calls == 2

        super
      end
    end

    Aws::SQS::Client.prepend(FailSecondSend)
  RUBY
  path
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
  bodies = Array.new(25) { |i| format('message-%02d', i) }
  bodies.each { |body| Shoryuken::Client.sqs.send_message(queue_url: queue_url(source), message_body: body) }

  with_queue_and_dir do |target, _target_dir|
    env = { 'RUBYOPT' => "#{ENV.fetch('RUBYOPT', '')} -r#{write_injection(dir)}" }
    status, output = run_shoryuken_sqs('mv', source, target, env: env)

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

# --- requeue ---
with_queue_and_dir do |target, dir|
  lines = Array.new(14) do |i|
    JSON.dump(message_id: "id-#{i}", body: "message-#{i}", attributes: {}, message_attributes: {})
  end
  # The second batch (lines 11-14) holds line 11 twice
  lines.insert(11, lines[10])
  path = File.join(dir, 'dump.jsonl')
  File.write(path, lines.join("\n"))

  status, output = run_shoryuken_sqs('requeue', target, path)

  assert_equal(1, status.exitstatus, "requeue must exit with 1, got: #{output}")
  assert_includes(
    output,
    "[FAIL] Could not requeue 5 messages from #{path} to #{target}: BatchEntryIdsNotDistinct " \
    "(Aws::SQS::Errors::BatchEntryIdsNotDistinct). Sent the first 10 lines of #{path}, resume from line 11",
    "got: #{output}"
  )
  refute(output.match?(BACKTRACE), "requeue must not print a backtrace, got: #{output}")
  assert_equal(10, queue_size(target), 'the first batch must be in the target')
end
