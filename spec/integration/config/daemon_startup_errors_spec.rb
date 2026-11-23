# frozen_string_literal: true

# This spec tests that `shoryuken start -d` reports the startup errors it can
# find before it forks in the launching process.
#
# The launching process prints the error as a one-line `[FAIL]` message, with
# no backtrace, and exits 1. An invalid option value fails before the workers
# are required and the pidfile is written. With nothing to require, a queue
# that does not exist fails the same way, with no pidfile.
#
# Regression: the process daemonized first, so these errors went only to the
# logfile and the launching process exited 0.

setup_sqs

with_queue_and_dir do |queue, dir|
  pidfile = File.join(dir, 'shoryuken.pid')
  logfile = File.join(dir, 'shoryuken.log')
  required = File.join(dir, 'required')
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    File.write('#{required}', '')

    class DaemonStartupErrorsWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body); end
    end
  RUBY

  # --- invalid option value ---
  status, output = run_shoryuken_until_exit(
    '-d', '-P', pidfile, '-L', logfile, '-r', boot_file, '-q', queue, '-c', '0'
  )
  assert_equal(1, status.exitstatus, "an invalid option value must exit 1, got: #{output}")
  assert_includes(output, '[FAIL]')
  assert_includes(output, 'concurrency')
  refute(output.include?('.rb:'), "an invalid option value must not print a backtrace, got: #{output}")
  refute(File.exist?(required), 'the workers must not be required before the options are valid')
  refute(File.exist?(pidfile), 'the process must fail before it forks and writes the pidfile')

  # --- missing queue, nothing to require ---
  missing = DT.uuid
  status, output = run_shoryuken_until_exit('-d', '-P', pidfile, '-L', logfile, '-q', missing)
  assert_equal(1, status.exitstatus, "a missing queue must exit 1, got: #{output}")
  assert_includes(output, "[FAIL] The specified queue(s) #{missing} do not exist")
  refute(output.include?('.rb:'), "a missing queue must not print a backtrace, got: #{output}")
  refute(File.exist?(pidfile), 'the process must fail before it forks and writes the pidfile')
end
