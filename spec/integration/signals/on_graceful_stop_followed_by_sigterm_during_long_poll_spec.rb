# frozen_string_literal: true

# This spec tests that a TERM sent while the graceful stop of a TSTP or a USR1 waits for an in-flight long poll stops
# `shoryuken start` within the shutdown timeout.
#
# It used to wait for the long poll to end (up to `wait_time_seconds`), because the signal loop ran the graceful stop
# and handled the TERM only after it. The process exits with status 0 and every lifecycle event fires once.

setup_sqs

with_queue_and_dir do |queue, dir|
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    Shoryuken.sqs_client_receive_message_opts = { wait_time_seconds: 20 }

    class GracefulStopThenTermWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body); end
    end

    %i[startup quiet shutdown stopped].each do |event|
      Shoryuken.on(event) { Shoryuken.logger.info("lifecycle event: \#{event}") }
    end
  RUBY

  %w[TSTP USR1].each do |graceful_signal|
    started_at = nil
    signal_sent_at = nil
    term_sent_at = nil
    status, output = run_shoryuken_until('-q', queue, '-t', '3', '-r', boot_file, signal: 'TERM') do |log, pid|
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      started_at ||= now if log.include?('lifecycle event: startup')
      signal_sent_at ||= started_at && now - started_at > 1 && Process.kill(graceful_signal, pid) && now
      term_sent_at = now if signal_sent_at && log.include?('lifecycle event: quiet') && now - signal_sent_at > 1
      term_sent_at
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - term_sent_at

    assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
    assert_includes(output, "Received #{graceful_signal}", "got: #{output}")
    assert_includes(output, 'Received TERM, will shutdown', "got: #{output}")
    assert(elapsed < 8, "TERM must stop the process within the timeout, took #{elapsed.round(2)} s: #{output}")

    events = output.scan(/lifecycle event: (\w+)/).flatten
    assert_equal(%w[startup quiet shutdown stopped], events, "every lifecycle event must fire once, got: #{output}")
  end
end
