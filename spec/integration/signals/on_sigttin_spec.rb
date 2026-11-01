# frozen_string_literal: true

# This spec tests that TTIN makes `shoryuken start` log the backtraces of all its threads without stopping it.
#
# On TTIN the process logs a `Thread TID-<id> <label>` line for every thread, each followed by its
# backtrace, including threads the app started itself. The process keeps working afterwards: it still processes a
# message sent after the dump, and TERM then exits it with status 0.

setup_sqs

with_queue_and_dir do |queue, dir|
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class TtinWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, body)
        Shoryuken.logger.info("processed: \#{body}")
      end
    end

    def ttin_probe_wait
      sleep
    end

    def ttin_unlabelled_wait
      sleep
    end

    Thread.new { ttin_probe_wait }['label'] = 'ttin-probe'
    Thread.new { ttin_unlabelled_wait }

    Shoryuken.on(:startup) { Shoryuken.logger.info('lifecycle event: startup') }
  RUBY

  ttin_sent = false
  message_sent = false
  status, output = run_shoryuken_until('-q', queue, '-r', boot_file, signal: 'TERM') do |log, pid|
    ttin_sent ||= log.include?('lifecycle event: startup') && Process.kill('TTIN', pid)

    if !message_sent && log.include?('ttin_probe_wait') && log.include?('ttin_unlabelled_wait')
      Shoryuken::Client.queues(queue).send_message(message_body: 'after TTIN')
      message_sent = true
    end

    log.include?('processed: after TTIN')
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received TERM, will shutdown', "got: #{output}")

  assert(output.match?(/Thread TID-[0-9a-z]+ ttin-probe$/), "TTIN must log the app's thread, got: #{output}")
  assert_includes(output, 'ttin_unlabelled_wait', "TTIN must log unlabelled threads too, got: #{output}")
  assert_includes(output, 'print_threads_backtrace', "TTIN must log the main thread's backtrace, got: #{output}")
end
