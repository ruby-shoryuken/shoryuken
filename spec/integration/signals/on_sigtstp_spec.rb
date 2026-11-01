# frozen_string_literal: true

# This spec tests that TSTP stops `shoryuken start` gracefully and keeps the process running until TERM.
#
# After TSTP the busy worker finishes its message (which is then deleted), no new message is
# fetched, and the process stays up. Only the TERM that follows exits it, with status 0.

setup_sqs

with_queue_and_dir do |queue, dir|
  started = File.join(dir, 'started')
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class TstpWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, body)
        File.write('#{started}', '')
        sleep 2
        Shoryuken.logger.info("performed: \#{body}")
      end
    end

    Shoryuken.on(:stopped) { Shoryuken.logger.info('lifecycle event: stopped') }
  RUBY

  Shoryuken::Client.queues(queue).send_message(message_body: 'in flight')

  tstp_sent = false
  stopped_at = nil
  status, output = run_shoryuken_until('-q', queue, '-r', boot_file, signal: 'TERM') do |log, pid|
    tstp_sent ||= File.exist?(started) && Process.kill('TSTP', pid)

    if !stopped_at && log.include?('lifecycle event: stopped')
      stopped_at = Time.now
      Shoryuken::Client.queues(queue).send_message(message_body: 'after stop')
    end

    # Long enough for a still-polling fetcher to pick up the new message
    stopped_at && Time.now - stopped_at > 5
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received TSTP, will stop accepting new work', "got: #{output}")
  performed_at = output.index('performed: in flight')
  assert(
    performed_at && performed_at < output.index('lifecycle event: stopped'),
    "the busy worker must finish before the stop completes, got: #{output}"
  )
  refute(output.include?('performed: after stop'), "no new message must be processed after TSTP, got: #{output}")
  assert_includes(output, 'Received TERM, will shutdown', "the process must stay up until TERM, got: #{output}")
  assert_equal(1, queue_size(queue), 'only the message sent after TSTP must be left in the queue')
end
