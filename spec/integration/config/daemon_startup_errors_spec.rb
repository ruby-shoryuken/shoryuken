# frozen_string_literal: true

# This spec tests that `shoryuken start -d` reports the startup errors it can
# find before it forks in the launching process.
#
# An invalid option value makes the launching process exit 1 with the error,
# before it requires the workers and writes the pidfile. With nothing to
# require, a queue that does not exist makes it exit 1 with the error and no
# pidfile.
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
  assert_includes(output, 'Shoryuken::Errors::InvalidConfigurationError')
  assert_includes(output, 'concurrency')
  refute(File.exist?(required), 'the workers must not be required before the options are valid')
  refute(File.exist?(pidfile), 'the process must fail before it forks and writes the pidfile')

  # --- missing queue, nothing to require ---
  missing = DT.uuid
  status, output = run_shoryuken_until_exit('-d', '-P', pidfile, '-L', logfile, '-q', missing)
  assert_equal(1, status.exitstatus, "a missing queue must exit 1, got: #{output}")
  assert_includes(output, "The specified queue(s) #{missing} do not exist")
  refute(File.exist?(pidfile), 'the process must fail before it forks and writes the pidfile')
end
