# frozen_string_literal: true

# This spec tests `shoryuken sqs` called with a class option (`-e`/`--endpoint`) before the command.
#
# Expected behavior: `sqs -e URL <command>` fails with "Options must follow the command", shows the command with the
# options after it and exits with status 1. `sqs -e URL` with no command still prints the command list and exits with
# status 0, and the options after the command still work.
#
# Regression: Thor found no command, ran `help` for the command name and exited with status 0, so the command never
# ran.

setup_sqs

endpoint = SHORYUKEN_ENV['AWS_ENDPOINT_URL_SQS']

with_queue_and_dir do |queue, _dir|
  # --- class option before the command ---
  status, output = run_shoryuken_command_until_exit('sqs', '-e', endpoint, 'ls', queue)
  assert_equal(1, status.exitstatus, "must exit with status 1, got: #{output}")
  assert_includes(output, "Options must follow the command: shoryuken sqs ls #{queue} -e #{endpoint}")
  refute(output.include?('Usage:'), "must not print help, got: #{output}")

  status, output = run_shoryuken_command_until_exit('sqs', "--endpoint=#{endpoint}", 'purge', queue)
  assert_equal(1, status.exitstatus, "must exit with status 1, got: #{output}")
  assert_includes(output, "Options must follow the command: shoryuken sqs purge #{queue} --endpoint=#{endpoint}")

  # --- class option before an unknown option ---
  status, output = run_shoryuken_command_until_exit('sqs', '-e', endpoint, '--bogus', 'ls')
  assert_equal(1, status.exitstatus, "must exit with status 1, got: #{output}")
  assert_includes(output, 'Unknown switches "--bogus"')

  # --- no command ---
  status, output = run_shoryuken_command_until_exit('sqs', '-e', endpoint)
  assert(status.success?, "sqs -e URL must exit with status 0, got: #{output}")
  assert_includes(output, 'shoryuken sqs ls [QUEUE-NAME-PREFIX]')

  # --- class option after the command ---
  status, output = run_shoryuken_sqs('ls', queue)
  assert(status.success?, "sqs ls -e URL must exit with status 0, got: #{output}")
  assert_includes(output, queue)
end
