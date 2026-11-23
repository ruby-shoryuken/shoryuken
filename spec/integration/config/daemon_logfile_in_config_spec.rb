# frozen_string_literal: true

# This spec tests that the daemon needs a logfile from the merged options: the
# config file or the CLI.
#
# `daemon: true` in the config file without a logfile makes `shoryuken check`
# fail and `shoryuken start` exit 1 before it forks, with no pidfile. A
# `logfile` in the config file with `-d` on the CLI is accepted: `check` passes,
# and `start` daemonizes, writes its log to that logfile and processes messages.
#
# Regression: the check read only the CLI options. `daemon: true` in the config
# file passed `check`, and `start` exited 0 while the daemon crashed with a
# TypeError; a config file `logfile` with `-d` was rejected (#526).

setup_sqs

def write_config(dir, name, config)
  path = File.join(dir, "#{name}.yml")
  File.write(path, config)
  path
end

def write_worker(dir, queue, record)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class DaemonLogfileWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, body)
        File.write('#{record}', "\#{body}\\n", mode: 'a')
      end
    end
  RUBY
  boot_file
end

def wait_for_record(record, logfile)
  Timeout.timeout(30) { sleep 0.1 until File.exist?(record) }
rescue Timeout::Error
  raise IntegrationsHelper::TestFailure, "the daemon must process the message, log: #{File.read(logfile)}"
end

with_queue_and_dir do |queue, dir|
  record = File.join(dir, 'processed')
  pidfile = File.join(dir, 'shoryuken.pid')
  logfile = File.join(dir, 'shoryuken.log')
  boot_file = write_worker(dir, queue, record)

  # --- daemon in the config file, no logfile ---
  no_logfile = write_config(dir, 'no_logfile', "daemon: true\npidfile: #{pidfile}\nqueues:\n  - #{queue}\n")

  status, output = run_shoryuken_command_until_exit('check', '-C', no_logfile, '-r', boot_file)
  assert_equal(1, status.exitstatus, "check must fail, got: #{output}")
  assert_includes(output, "[FAIL] You should set a logfile if you're going to daemonize")

  status, output = run_shoryuken_until_exit('-C', no_logfile, '-r', boot_file)
  assert_equal(1, status.exitstatus, "start must fail in the launching process, got: #{output}")
  assert_includes(output, "You should set a logfile if you're going to daemonize")
  refute(File.exist?(pidfile), 'start must fail before it forks and writes the pidfile')

  # --- logfile in the config file, -d on the CLI ---
  with_logfile = write_config(dir, 'with_logfile', "logfile: #{logfile}\nqueues:\n  - #{queue}\n")

  status, output = run_shoryuken_command_until_exit('check', '-d', '-C', with_logfile, '-r', boot_file)
  assert_equal(0, status.exitstatus, "check must accept the config file logfile, got: #{output}")
  assert_includes(output, 'Configuration OK')

  with_shoryuken_daemon(pidfile, logfile, '-C', with_logfile, '-r', boot_file, cli_logfile: false) do |status, output, pid|
    assert(status.success?, "the launching process must exit cleanly, got #{status.inspect}: #{output}")
    assert(process_alive?(pid), "the daemon must run after the launching process exited, log: #{File.read(logfile)}")

    Shoryuken::Client.queues(queue).send_message(message_body: 'logfile from config')

    wait_for_record(record, logfile)
    assert_equal("logfile from config\n", File.read(record))
    assert_includes(File.read(logfile), 'Starting', 'the log must go to the config file logfile')
    assert(stop_process(pid), "TERM must stop the daemon, log: #{File.read(logfile)}")
  end
end
