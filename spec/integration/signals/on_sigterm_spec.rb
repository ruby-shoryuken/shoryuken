# frozen_string_literal: true

# This spec tests that TERM hard-shuts `shoryuken start` down within `timeout`
# while a worker is still busy, and that the in-flight message is released.
#
# After TERM the process exits with status 0 within the configured `timeout`
# (plus a margin), without waiting for the busy worker to finish. The killed
# worker's message is not deleted (auto_delete runs only after `perform`
# returns) and is visible again right after the exit, long before the queue's
# visibility timeout.
#
# It used to stay in flight for the whole visibility timeout.
#
# Regression: #215 - a hard shutdown hung while some workers were busy
# (CHANGELOG v2.0.7, "Fix hard shutdown if there are some busy workers").

def write_busy_worker(dir, queue, started, finished)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class HardShutdownWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{started}', '')
        sleep 60
        File.write('#{finished}', '')
      end
    end
  RUBY
  boot_file
end

setup_sqs

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
  started = File.join(dir, 'started')
  finished = File.join(dir, 'finished')
  boot_file = write_busy_worker(dir, queue, started, finished)

  Shoryuken::Client.queues(queue).send_message(message_body: 'in flight')

  signal_at = nil
  status, output = run_shoryuken_until('-q', queue, '-t', '2', '-r', boot_file, signal: 'TERM') do
    File.exist?(started) && (signal_at ||= Time.now)
  end
  shutdown_time = Time.now - signal_at

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received TERM, will shutdown', "got: #{output}")
  assert(shutdown_time < 7, "the process must exit within the timeout, took #{shutdown_time.round(1)}s: #{output}")
  refute(File.exist?(finished), 'the busy worker must be killed, not awaited')

  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  messages = Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 5).messages
  assert_equal(['in flight'], messages.map(&:body), 'the killed worker\'s message must be visible again at once')
end
