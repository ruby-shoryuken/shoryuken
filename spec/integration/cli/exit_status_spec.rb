# frozen_string_literal: true

# This spec tests the exit status of `shoryuken` commands called with input Thor rejects.
#
# Expected behavior: an unknown command, an unknown option or an extra argument prints the error and exits with
# status 1, for `start`, `version` and the `sqs` subcommands. Valid calls still exit with status 0.
#
# Regression: Thor printed the error and a deprecation warning and exited with status 0; an unknown option of a
# command with an optional argument (`sqs ls --bogus`) was taken as that argument.

setup_sqs

def assert_rejected(status, output, message)
  refute(status.success?, "must exit with a non-zero status, got: #{output}")
  assert_equal(1, status.exitstatus, "must exit with status 1, got: #{output}")
  assert_includes(output, message, "got: #{output}")
  refute(output.include?('Deprecation warning'), "got: #{output}")
end

# --- unknown option ---
status, output = run_shoryuken_until_exit('--bogus')
assert_rejected(status, output, 'Unknown switches "--bogus"')

status, output = run_shoryuken_command_until_exit('version', '--bogus')
assert_rejected(status, output, 'Unknown switches "--bogus"')

status, output = run_shoryuken_sqs('ls', '--bogus')
assert_rejected(status, output, 'Unknown switches "--bogus"')

# --- extra argument ---
status, output = run_shoryuken_until_exit('extra')
assert_rejected(status, output, 'ERROR: "shoryuken start" was called with arguments ["extra"]')

status, output = run_shoryuken_command_until_exit('version', 'extra')
assert_rejected(status, output, 'ERROR: "shoryuken version" was called with arguments ["extra"]')

status, output = run_shoryuken_sqs('ls', 'a', 'b')
assert_rejected(status, output, 'ERROR: "shoryuken sqs ls" was called with arguments ["a", "b"]')

# --- unknown command ---
status, output = run_shoryuken_command_until_exit('bogus')
assert_rejected(status, output, 'Could not find command "bogus"')

status, output = run_shoryuken_sqs('bogus')
assert_rejected(status, output, 'Could not find command "bogus"')

# --- valid calls ---
status, output = run_shoryuken_command_until_exit('version')
assert(status.success?, "version must exit with status 0, got: #{output}")
assert_includes(output, "Shoryuken #{Shoryuken::VERSION}", "got: #{output}")

with_queue_and_dir do |queue, _dir|
  status, output = run_shoryuken_sqs('ls', queue)
  assert(status.success?, "sqs ls must exit with status 0, got: #{output}")
  assert_includes(output, queue, "got: #{output}")
end
