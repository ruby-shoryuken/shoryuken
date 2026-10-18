# frozen_string_literal: true

# This spec tests that `shoryuken start` refuses to boot a worker whose
# `shoryuken_options` has an unknown key, and boots one that uses every known
# worker option.
#
# Expected behavior: a mistyped key (`auto_delte`) raises
# InvalidConfigurationError naming the worker and the key when the worker
# class loads, so the process exits with a non-zero status and processes
# nothing. A worker with only known options starts and processes the message.
#
# Regression: any key was merged into the worker options without a check, so a
# typo was silently ignored (e.g. messages were never deleted).

setup_sqs

def write_worker(dir, name, options, marker)
  boot_file = File.join(dir, "#{name}.rb")
  File.write(boot_file, <<~RUBY)
    class #{name}
      include Shoryuken::Worker

      shoryuken_options #{options}

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY
  boot_file
end

dir = Dir.mktmpdir
queue = DT.uuid
create_test_queue(queue)

marker = File.join(dir, 'processed')
config_file = File.join(dir, 'shoryuken.yml')
File.write(config_file, "queues:\n  - #{queue}\n")

Shoryuken::Client.queues(queue).send_message(message_body: 'hello')

begin
  # --- unknown key ---
  boot_file = write_worker(dir, 'TypoWorker', "queue: '#{queue}', auto_delte: true", marker)

  status, output = run_shoryuken_until_exit('-C', config_file, '-r', boot_file)

  refute(status.success?, "the process must fail to start, got: #{output}")
  assert_includes(output, 'Shoryuken::Errors::InvalidConfigurationError', "got: #{output}")
  assert_includes(output, 'TypoWorker.auto_delte', "got: #{output}")
  assert_includes(output, 'is not a known worker option', "got: #{output}")
  refute(output.include?('Starting'), "the process must not start, got: #{output}")

  refute(File.exist?(marker), 'no message must be processed')
  assert_equal(1, queue_size(queue), 'the message must still be in the queue')

  # --- every known option ---
  boot_file = write_worker(
    dir, 'KnownOptionsWorker',
    "queue: '#{queue}', delete: false, auto_delete: true, auto_visibility_timeout: true, " \
    'retry_intervals: [1], batch: false, body_parser: :text, non_retryable_exceptions: [ArgumentError]',
    marker
  )

  status, output = run_shoryuken_until('-C', config_file, '-r', boot_file) { File.exist?(marker) }

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
  refute(output.include?('InvalidConfigurationError'), "got: #{output}")
ensure
  delete_test_queue(queue)
  FileUtils.remove_entry(dir)
end
