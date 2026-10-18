# frozen_string_literal: true

# This spec tests that TERM hard-shuts `shoryuken start` down within `timeout`
# while a worker is still busy, and that the in-flight message is kept.
#
# Expected behavior: after TERM the process exits with status 0 within the
# configured `timeout` (plus a margin), without waiting for the busy worker to
# finish. The killed worker's message is not deleted (auto_delete runs only
# after `perform` returns), so it becomes visible again after the queue's
# visibility timeout.
#
# Regression: #215 - a hard shutdown hung while some workers were busy
# (CHANGELOG v2.0.7, "Fix hard shutdown if there are some busy workers").

setup_sqs

dir = Dir.mktmpdir
queue = DT.uuid
create_test_queue(queue, attributes: { 'VisibilityTimeout' => '5' })

begin
  started = File.join(dir, 'started')
  finished = File.join(dir, 'finished')
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class SigtermWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{started}', '')
        sleep 60
        File.write('#{finished}', '')
      end
    end
  RUBY

  Shoryuken::Client.queues(queue).send_message(message_body: 'in flight')

  term_at = nil
  status, output = run_shoryuken_until('-q', queue, '-t', '2', '-r', boot_file) do
    File.exist?(started) && (term_at ||= Time.now)
  end
  shutdown_time = Time.now - term_at

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received TERM, will shutdown', "got: #{output}")
  assert(shutdown_time < 7, "the process must exit within the timeout, took #{shutdown_time.round(1)}s: #{output}")
  refute(File.exist?(finished), 'the busy worker must be killed, not awaited')

  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  messages = Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 15).messages
  assert_equal(['in flight'], messages.map(&:body), 'the in-flight message must come back after the visibility timeout')
ensure
  delete_test_queue(queue)
  FileUtils.remove_entry(dir)
end
