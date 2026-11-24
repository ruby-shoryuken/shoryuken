# frozen_string_literal: true

# This spec tests that a USR1 sent after the graceful stop of a TSTP has ended exits `shoryuken start` with status 0,
# and that the second signal does not run the shutdown sequence again.

setup_sqs

with_queue_and_dir do |queue, dir|
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class TstpThenUsr1Worker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body); end
    end

    %i[startup quiet shutdown stopped].each do |event|
      Shoryuken.on(event) { Shoryuken.logger.info("lifecycle event: \#{event}") }
    end
  RUBY

  tstp_sent = false
  status, output = run_shoryuken_until('-q', queue, '-r', boot_file, signal: 'USR1', timeout: 10) do |log, pid|
    tstp_sent ||= log.include?('lifecycle event: startup') && Process.kill('TSTP', pid)
    log.include?('lifecycle event: stopped')
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received USR1, will soft shutdown', "got: #{output}")

  events = output.scan(/lifecycle event: (\w+)/).flatten
  assert_equal(%w[startup quiet shutdown stopped], events, "every lifecycle event must fire once, got: #{output}")
end
