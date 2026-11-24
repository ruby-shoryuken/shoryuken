# frozen_string_literal: true

# This spec tests that a TERM sent while the graceful stop of a TSTP runs a slow `stop_callback` lets the callback
# finish and fires the shutdown event before the process stops.
#
# The process exits with status 0, the callback ends, and the quiet, shutdown and stopped events fire once, in this
# order.

setup_sqs

with_queue_and_dir do |queue, dir|
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class TstpThenTermCallbackWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body); end
    end

    Shoryuken.on_stop do
      Shoryuken.logger.info('stop_callback started')
      sleep 2
      Shoryuken.logger.info('stop_callback finished')
    end

    %i[startup quiet shutdown stopped].each do |event|
      Shoryuken.on(event) { Shoryuken.logger.info("lifecycle event: \#{event}") }
    end
  RUBY

  tstp_sent = false
  status, output = run_shoryuken_until('-q', queue, '-t', '3', '-r', boot_file, signal: 'TERM') do |log, pid|
    tstp_sent ||= log.include?('lifecycle event: startup') && Process.kill('TSTP', pid)
    log.include?('stop_callback started')
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received TERM, will shutdown', "got: #{output}")
  assert_includes(output, 'stop_callback finished', "the stop_callback must finish, got: #{output}")

  events = output.scan(/lifecycle event: (\w+)/).flatten
  assert_equal(%w[startup quiet shutdown stopped], events, "every lifecycle event must fire once, got: #{output}")
end
