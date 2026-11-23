# frozen_string_literal: true

# This spec tests that `shoryuken check` fails for a worker whose `perform`
# cannot take the message and its body, and that `shoryuken start` logs the same
# problem as a warning and still boots.
#
# The processor calls `perform(sqs_msg, body)`. A Sidekiq-style
# `perform(name)` or a typo (`preform`) used to pass `check` and fail on every
# message, which came back after each visibility timeout.

setup_sqs

def write_worker(dir, name, queue, definition)
  worker_file = File.join(dir, "#{name}.rb")
  File.write(worker_file, <<~RUBY)
    class #{name}
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      #{definition}
    end
  RUBY
  worker_file
end

with_queue_and_dir do |queue, dir|
  # --- perform with one argument ---
  worker_file = write_worker(dir, 'SigWorker', queue, 'def perform(name); end')

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(1, status.exitstatus, "a wrong perform signature must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] SigWorker#perform must accept (sqs_msg, body); it takes (name)')
  refute(output.include?('Configuration OK'), "got: #{output}")
  refute(output.include?('WARN'), "problems must be reported once, not also logged as warnings, got: #{output}")
  refute(output.include?('.rb:'), "a wrong perform signature must not print a backtrace, got: #{output}")

  status, output = run_shoryuken_until('-q', queue, '-r', worker_file) { |log| log.include?('Starting') }
  assert_includes(
    output, 'WARN: SigWorker#perform must accept (sqs_msg, body); it takes (name)', "got: #{output}"
  )
  assert_includes(output, 'Starting', "start must keep booting, got: #{output}")
  assert(status.success?, "start must keep booting and stop cleanly, got: #{output}")

  # --- no perform ---
  worker_file = write_worker(dir, 'TypoWorker', queue, 'def preform(_sqs_msg, _body); end')

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(1, status.exitstatus, "a missing perform must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] TypoWorker must define perform(sqs_msg, body)')

  # --- perform with the message and body ---
  worker_file = write_worker(dir, 'GoodWorker', queue, 'def perform(_sqs_msg, _body); end')

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(0, status.exitstatus, "a valid perform must exit 0, got: #{output}")
  assert_includes(output, 'Configuration OK')
end
