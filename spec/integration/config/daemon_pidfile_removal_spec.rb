# frozen_string_literal: true

# This spec tests that a daemon removes its pidfile when it exits, but only
# while the file holds its own pid.
#
# TERM stops the daemon and removes the pidfile. A daemon that fails to start
# after it forked (a missing queue next to required workers) removes it too. A
# pidfile that another process overwrote with its pid is kept.
#
# Regression: the pidfile was never removed, so after a stop or a failed start
# it held a dead pid.

setup_sqs

def wait_for(message, timeout: 30)
  Timeout.timeout(timeout) { sleep 0.1 until yield }
rescue Timeout::Error
  raise IntegrationsHelper::TestFailure, message
end

def write_worker(dir, queue)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class DaemonPidfileWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body); end
    end
  RUBY
  boot_file
end

def expect_failed_start_removes_pidfile(pidfile, logfile, boot_file)
  missing = DT.uuid
  status, output = run_shoryuken_until_exit('-d', '-P', pidfile, '-L', logfile, '-r', boot_file, '-q', missing)
  assert(status.success?, "the launching process exits before the daemon loads the queues, got: #{output}")

  wait_for("the daemon must fail on the missing queue, log: #{File.read(logfile)}") do
    File.read(logfile).include?("The specified queue(s) #{missing} do not exist")
  end
  wait_for("the failed daemon must remove its pidfile, log: #{File.read(logfile)}") { !File.exist?(pidfile) }

  log = File.read(logfile)
  assert_includes(log, 'Shoryuken::Errors::QueueNotFoundError', 'an error after the fork must keep its class')
  refute(log.include?('[FAIL]'), "an error after the fork must not be printed as [FAIL], log: #{log}")
end

with_queue_and_dir do |queue, dir|
  pidfile = File.join(dir, 'shoryuken.pid')
  logfile = File.join(dir, 'shoryuken.log')
  boot_file = write_worker(dir, queue)

  # --- TERM ---
  with_shoryuken_daemon(pidfile, logfile, '-r', boot_file, '-q', queue) do |_status, _output, pid|
    wait_for("the daemon must start, log: #{File.read(logfile)}") { File.read(logfile).include?('Starting') }

    assert(stop_process(pid), "TERM must stop the daemon, log: #{File.read(logfile)}")
    refute(File.exist?(pidfile), "the daemon must remove its pidfile, log: #{File.read(logfile)}")
  end

  # --- pidfile overwritten by another process ---
  other = Process.spawn('sleep', '60')
  other_pid = "#{other}\n"

  with_shoryuken_daemon(pidfile, logfile, '-r', boot_file, '-q', queue) do |_status, _output, pid|
    wait_for("the daemon must start, log: #{File.read(logfile)}") { File.read(logfile).scan('Starting').size == 2 }
    File.write(pidfile, other_pid)

    assert(stop_process(pid), "TERM must stop the daemon, log: #{File.read(logfile)}")
    assert_equal(other_pid, File.read(pidfile), 'the daemon must keep a pidfile that holds another pid')
  end

  Process.wait(other)

  File.delete(pidfile)

  # --- failed start after the fork ---
  expect_failed_start_removes_pidfile(pidfile, logfile, boot_file)
end
