# frozen_string_literal: true

def expect_hard_shutdown(signal)
  with_queue_and_dir(attributes: { 'VisibilityTimeout' => '5' }) do |queue, dir|
    started = File.join(dir, 'started')
    finished = File.join(dir, 'finished')
    boot_file = write_busy_worker(dir, queue, started, finished)

    Shoryuken::Client.queues(queue).send_message(message_body: 'in flight')

    signal_at = nil
    status, output = run_shoryuken_until('-q', queue, '-t', '2', '-r', boot_file, signal: signal) do
      File.exist?(started) && (signal_at ||= Time.now)
    end
    shutdown_time = Time.now - signal_at

    assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
    assert_includes(output, "Received #{signal}, will shutdown", "got: #{output}")
    assert(shutdown_time < 7, "the process must exit within the timeout, took #{shutdown_time.round(1)}s: #{output}")
    refute(File.exist?(finished), 'the busy worker must be killed, not awaited')

    queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
    messages = Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 15).messages
    assert_equal(['in flight'], messages.map(&:body), 'the in-flight message must come back after the visibility timeout')
  end
end

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
