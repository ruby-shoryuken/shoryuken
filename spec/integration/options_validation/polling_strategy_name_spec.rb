# frozen_string_literal: true

# This spec tests that `shoryuken check` and `shoryuken start` reject a
# polling strategy name that resolves to no strategy, globally or in a group,
# and accept a custom strategy defined in a `-r` file.
#
# `check` prints `[FAIL]` with the key path and exits 1 without a backtrace.
# `start` prints `[FAIL]` to stderr with the message and the error class
# (InvalidPollingStrategyError, an InvalidConfigurationError) without a
# backtrace and exits 1 before it starts; the message waiting in the queue is
# not processed. A global name is used only by the default group, so without
# top-level queues it is not checked and `start` processes as before.
#
# It used to pass `check` with "Configuration OK" and fail only when the
# launcher built the managers.

setup_sqs

MESSAGE = 'needs to be WeightedRoundRobin, StrictPriority or the name of a defined class'

def write_config(dir, config)
  config_file = File.join(dir, "#{DT.uuid}.yml")
  File.write(config_file, config)
  config_file
end

def expect_check_rejected(dir, boot_file, config, key)
  status, output = run_shoryuken_command_until_exit('check', '-C', write_config(dir, config), '-r', boot_file)

  assert_equal(1, status.exitstatus, "check must exit 1, got: #{output}")
  assert_includes(output, '[FAIL]', "got: #{output}")
  assert_includes(output, key, "got: #{output}")
  assert_includes(output, MESSAGE, "got: #{output}")
  refute(output.include?('.rb:'), "check must not print a backtrace, got: #{output}")
end

def expect_start_rejected(dir, boot_file, config, key)
  status, stdout, output = run_shoryuken_command_until_exit_split(
    'start', '-C', write_config(dir, config), '-r', boot_file
  )

  assert_equal(1, status.exitstatus, "the process must fail to start, got: #{stdout}#{output}")
  assert_includes(output, '[FAIL]', "the error must go to stderr, got: #{output}, stdout: #{stdout}")
  assert_includes(output, 'Shoryuken::Errors::InvalidPollingStrategyError', "got: #{output}")
  refute(output.include?('.rb:'), "start must not print a backtrace, got: #{output}")
  assert_includes(output, key, "got: #{output}")
  assert_includes(output, MESSAGE, "got: #{output}")
  refute(stdout.include?('[FAIL]'), "the error must not go to stdout, got: #{stdout}")
  refute(stdout.include?('Starting'), "the process must not start, got: #{stdout}")
end

def write_boot_file(dir, queue, marker)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class RequiredFileStrategy < Shoryuken::Polling::WeightedRoundRobin
    end

    class PollingStrategyNameWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY
  boot_file
end

with_queue_and_dir do |queue, dir|
  marker = File.join(dir, 'processed')
  boot_file = write_boot_file(dir, queue, marker)

  Shoryuken::Client.queues(queue).send_message(message_body: 'must not be processed')

  global = "polling_strategy: NoSuchStrategy\nqueues:\n  - #{queue}\n"
  group = "groups:\n  custom:\n    polling_strategy: NoSuchStrategy\n    queues:\n      - #{queue}\n"

  # --- check ---
  expect_check_rejected(dir, boot_file, global, 'polling_strategy')
  expect_check_rejected(dir, boot_file, group, 'groups.custom.polling_strategy')

  # --- start ---
  expect_start_rejected(dir, boot_file, global, 'polling_strategy')
  expect_start_rejected(dir, boot_file, group, 'groups.custom.polling_strategy')

  refute(File.exist?(marker), 'no message must be processed')
  assert_equal(1, queue_size(queue), 'the message must still be in the queue')

  # --- a strategy defined in a required file ---
  [global, group].each do |config|
    config_file = write_config(dir, config.sub('NoSuchStrategy', 'RequiredFileStrategy'))
    status, output = run_shoryuken_command_until_exit('check', '-C', config_file, '-r', boot_file)

    assert_equal(0, status.exitstatus, "a strategy from a -r file must be accepted, got: #{output}")
    assert_includes(output, 'Configuration OK')
  end

  # --- an unknown global name with only groups ---
  config = "polling_strategy: NoSuchStrategy\ngroups:\n  custom:\n    queues:\n      - #{queue}\n"
  status, output = run_shoryuken_until('-C', write_config(dir, config), '-r', boot_file) { File.exist?(marker) }

  assert(status.success?, "an unused global name must not stop the process, got #{status.inspect}: #{output}")
  assert(File.exist?(marker), "the message must be processed, got: #{output}")
end
