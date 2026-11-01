# frozen_string_literal: true

# This spec tests that `shoryuken start` refuses to run when a configured queue does not exist, with the queues
# given on the CLI or in a config file group.
#
# The process exits on its own with a non-zero status before it starts. The QueueNotFoundError
# is printed once and names every missing queue, but not the existing one, with a hint to create them. The process
# never polls, so the log has no manager failure from a poll, and the message waiting in the existing queue is not
# processed.
#
# Regression: #172 (shoryuken started anyway and spammed the log with a fetch error per poll), #150 (the raw
# NonExistentQueue error did not say which queue was missing).

setup_sqs

def expect_missing_queues_rejected(queue, missing, *args)
  status, output = run_shoryuken_until_exit(*args, timeout: 10)

  refute(status.success?, "the process must fail to start, got: #{output}")
  assert_includes(output, 'Shoryuken::Errors::QueueNotFoundError', "got: #{output}")
  assert_includes(output, "The specified queue(s) #{missing.join(', ')} do not exist.", "got: #{output}")
  assert_includes(output, "Try 'shoryuken sqs create QUEUE-NAME'", "got: #{output}")
  assert_equal(1, output.scan('do not exist').size, "the error must be printed once, got: #{output}")
  refute(output.include?("#{queue} do not exist"), "the existing queue must not be named, got: #{output}")
  refute(output.include?('Starting'), "the process must not start, got: #{output}")
  refute(output.include?('Manager failed'), "the process must not poll, got: #{output}")
  refute(output.include?('The specified queue does not exist'), "the process must not poll, got: #{output}")
end

with_queue_and_dir do |queue, dir|
  marker = File.join(dir, 'processed')
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class NonexistentQueueWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY

  Shoryuken::Client.queues(queue).send_message(message_body: 'must not be processed')

  missing = DT.uuids(2)

  # --- CLI ---
  expect_missing_queues_rejected(queue, missing, '-r', boot_file, '-q', queue, *missing)

  # --- config file group ---
  config_file = File.join(dir, 'shoryuken.yml')
  File.write(config_file, <<~YAML)
    groups:
      custom:
        concurrency: 1
        queues:
          - #{queue}
          - #{missing.first}
          - #{missing.last}
  YAML
  expect_missing_queues_rejected(queue, missing, '-C', config_file, '-r', boot_file)

  assert_equal(1, queue_size(queue), 'the waiting message must not be processed')
  refute(File.exist?(marker), 'the worker must not run')
end
