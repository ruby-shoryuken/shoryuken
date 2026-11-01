# frozen_string_literal: true

# This spec tests that `shoryuken start -d -P <pidfile> -L <logfile>` runs as a
# daemon.
#
# The launching process exits with status 0 and prints no
# log; the daemon keeps running in its own session and processes messages; the
# pidfile holds the daemon pid; a thread the required files start keeps
# running, as the process daemonizes before it loads them; the log and the
# worker's stdout go to the logfile; TERM stops the daemon.
#
# Regression: `-d` crashed with `undefined local variable or method
# 'initialize_logger'` (#74).
#
# Regression: the process daemonized after it loaded the environment, so the
# fork killed the threads the app started while loading (#219, fixed for `-d`
# in #223 and #224).

setup_sqs

def processed(record)
  File.exist?(record) ? File.readlines(record, chomp: true) : []
end

with_queue_and_dir do |queue, dir|
  record = File.join(dir, 'processed')
  pidfile = File.join(dir, 'shoryuken.pid')
  logfile = File.join(dir, 'shoryuken.log')
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    BOOT_THREAD = Thread.new { sleep }

    class DaemonWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, body)
        puts "daemon worker stdout: \#{body}"
        File.write('#{record}', "\#{body} boot thread alive: \#{BOOT_THREAD.alive?}\\n", mode: 'a')
      end
    end
  RUBY

  with_shoryuken_daemon(pidfile, logfile, '-r', boot_file, '-q', queue) do |status, output, pid|
    assert(status.success?, "the launching process must exit cleanly, got #{status.inspect}: #{output}")
    refute(output.include?('Starting'), "the log must not go to the terminal, got: #{output}")
    assert(process_alive?(pid), "the daemon must run after the launching process exited, log: #{File.read(logfile)}")
    refute(Process.getsid(pid) == Process.getsid, 'the daemon must leave the launching session')

    # Sent after the launching process exited, so only the daemon can process it
    Shoryuken::Client.queues(queue).send_message(message_body: 'daemonized')

    begin
      Timeout.timeout(30) { sleep 0.1 until processed(record).any? }
    rescue Timeout::Error
      raise IntegrationsHelper::TestFailure, "the daemon must process the message, log: #{File.read(logfile)}"
    end

    assert_equal(
      ['daemonized boot thread alive: true'], processed(record),
      'the daemon must process the message and keep the thread started while loading'
    )

    log = File.read(logfile)
    assert_includes(log, 'Starting', 'the log must go to the logfile')
    assert_includes(log, 'daemon worker stdout: daemonized', 'stdout must go to the logfile')

    assert(stop_process(pid), "TERM must stop the daemon, log: #{File.read(logfile)}")
    assert_includes(File.read(logfile), 'Received TERM, will shutdown')
  end
end
