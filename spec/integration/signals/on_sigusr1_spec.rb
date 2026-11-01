# frozen_string_literal: true

# This spec tests that USR1 soft-shuts `shoryuken start` down: it stops fetching, finishes every message it already
# fetched and exits.
#
# After USR1 the process fires the quiet, shutdown and stopped events in this order and exits with
# status 0. It fetches no new messages, so part of the queue stays unprocessed and visible, and no fetched message is
# left in flight. A message returned by a receive that was in flight when USR1 came is processed too.
#
# Regression: #677 - a soft shutdown did not wait for an in-flight receive, so the messages it returned stayed in
# flight unprocessed (#539, fixed in v5.3.1 by #676).

def write_soft_shutdown_worker(dir, queue)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class SoftShutdownWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, body)
        File.write(File.join('#{dir}', "started-\#{body}"), '')
        sleep 1
        File.write(File.join('#{dir}', "processed-\#{body}"), '')
      end
    end

    %i[startup quiet shutdown stopped].each do |event|
      Shoryuken.on(event) { Shoryuken.logger.info("lifecycle event: \#{event}") }
    end
  RUBY
  boot_file
end

setup_sqs

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
  boot_file = write_soft_shutdown_worker(dir, queue)

  10.times { |i| Shoryuken::Client.queues(queue).send_message(message_body: "message-#{i}") }

  status, output = run_shoryuken_until('-q', queue, '-c', '2', '-r', boot_file, signal: 'USR1') do
    Dir.glob(File.join(dir, 'started-*')).any?
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received USR1, will soft shutdown', "got: #{output}")

  events = output.scan(/lifecycle event: (\w+)/).flatten
  assert_equal(%w[startup quiet shutdown stopped], events, "got: #{output}")

  started = Dir.glob(File.join(dir, 'started-*')).size
  processed = Dir.glob(File.join(dir, 'processed-*')).size
  assert_equal(started, processed, 'every started message must finish before the process exits')
  assert(processed < 10, "fetching must stop after USR1, but all 10 messages were processed: #{output}")

  counts = queue_counts(queue)
  assert_equal(0, counts[:in_flight], 'no fetched message may be left in flight')
  assert_equal(10 - processed, counts[:visible], 'unfetched messages must stay visible')
end

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60', 'ReceiveMessageWaitTimeSeconds' => '5' }) do |queue, dir|
  boot_file = write_soft_shutdown_worker(dir, queue)

  # The send must land inside the 5 s long poll that is in flight when USR1 arrives
  sender = nil
  status, output = run_shoryuken_until('-q', queue, '-c', '2', '-r', boot_file, '-v', signal: 'USR1') do |log, _pid|
    next false unless log.include?("Looking for new messages in #{queue}")

    sender ||= Thread.new do
      sleep 1.5
      Shoryuken::Client.queues(queue).send_message(message_body: 'late')
    end
  end
  sender.join

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert(File.exist?(File.join(dir, 'processed-late')), "the message of the in-flight receive must be processed: #{output}")
  assert_equal(0, queue_counts(queue)[:in_flight], 'no message may be left in flight')
end
