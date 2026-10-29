# frozen_string_literal: true

# This spec tests that USR1 soft-shuts `shoryuken start` down: it stops fetching, finishes every message it already
# fetched and exits.
#
# Expected behavior: after USR1 the process fires the quiet, shutdown and stopped events in this order and exits with
# status 0. It fetches no new messages, so part of the queue stays unprocessed and visible, and no fetched message is
# left in flight.
#
# Regression: #677 - a soft shutdown could exit without handling every message it fetched from SQS (#539, fixed in
# v5.3.1 by #676).

setup_sqs

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
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

  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  attributes = Shoryuken::Client.sqs.get_queue_attributes(
    queue_url: queue_url,
    attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
  ).attributes
  assert_equal('0', attributes['ApproximateNumberOfMessagesNotVisible'], 'no fetched message may be left in flight')
  assert_equal((10 - processed).to_s, attributes['ApproximateNumberOfMessages'], 'unfetched messages must stay visible')
end
