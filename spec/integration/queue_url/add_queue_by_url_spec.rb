# frozen_string_literal: true

# This spec tests `shoryuken start` with a queue configured by its URL instead
# of its name, in the config file and on the CLI.
#
# Expected behavior: a worker whose `queue` option is the same URL receives the
# message with its body, and with `auto_delete: true` the message is deleted
# from the queue after processing. No `No worker` error is logged.

setup_sqs

def expect_processed_by_url(dir, name, queue, queue_url, *args)
  marker = File.join(dir, "#{name}.processed")
  boot_file = File.join(dir, "#{name}_boot.rb")
  File.write(boot_file, <<~RUBY)
    class QueueUrlWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue_url}', auto_delete: true

      def perform(_sqs_msg, body)
        File.write('#{marker}', body)
      end
    end
  RUBY

  Shoryuken::Client.queues(queue).send_message(message_body: name)

  status, output = run_shoryuken_until('-r', boot_file, *args) { File.exist?(marker) }

  assert(status.success?, "#{name}: the process must exit cleanly, got #{status.inspect}: #{output}")
  assert_equal(name, File.read(marker), "#{name}: the worker must receive the message body")
  refute(output.include?('No worker'), "#{name}: the worker must be found by the queue URL, got: #{output}")
  assert_equal(0, queue_size(queue), "#{name}: the message must be deleted")
end

with_queue_and_dir do |queue, dir|
  queue_url = Shoryuken::Client.queues(queue).url
  assert(queue_url.start_with?('http://'), "expected a queue URL, got #{queue_url}")

  config_file = File.join(dir, 'shoryuken.yml')
  File.write(config_file, <<~YAML)
    queues:
      - ['#{queue_url}', 1]
  YAML

  # --- URL in the config file ---
  expect_processed_by_url(dir, 'config_file', queue, queue_url, '-C', config_file)

  # --- URL on the CLI ---
  expect_processed_by_url(dir, 'cli', queue, queue_url, '-q', queue_url)
end
