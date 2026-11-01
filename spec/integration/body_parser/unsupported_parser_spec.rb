# frozen_string_literal: true

# This spec tests that `shoryuken start` refuses to boot a worker whose
# `body_parser` is not a form Shoryuken can parse with, and boots one whose
# parser is an object responding to `parse`.
#
# An unsupported value (`:JSON`) raises
# InvalidConfigurationError naming the worker and `body_parser` when the worker
# class loads, so the process exits with a non-zero status and the message stays
# in the queue. A worker with `body_parser: JSON` starts and gets the parsed body.
#
# Regression: an unsupported value was accepted and every message got a nil
# body; with auto_delete the message was then deleted, so its content was lost.

setup_sqs

def write_worker(dir, name, queue, body_parser, marker)
  boot_file = File.join(dir, "#{name}.rb")
  File.write(boot_file, <<~RUBY)
    class #{name}
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true, body_parser: #{body_parser}

      def perform(_sqs_msg, body)
        File.write('#{marker}', body.inspect)
      end
    end
  RUBY
  boot_file
end

with_queue_and_dir do |queue, dir|
  marker = File.join(dir, 'processed')
  config_file = File.join(dir, 'shoryuken.yml')
  File.write(config_file, "queues:\n  - #{queue}\n")

  Shoryuken::Client.queues(queue).send_message(message_body: '{"id":1}')

  # --- unsupported body_parser ---
  boot_file = write_worker(dir, 'TypoParserWorker', queue, ':JSON', marker)

  status, output = run_shoryuken_until_exit('-C', config_file, '-r', boot_file)

  refute(status.success?, "the process must fail to start, got: #{output}")
  assert_includes(output, 'Shoryuken::Errors::InvalidConfigurationError', "got: #{output}")
  assert_includes(output, 'TypoParserWorker.body_parser', "got: #{output}")
  refute(output.include?('Starting'), "the process must not start, got: #{output}")

  refute(File.exist?(marker), 'no message must be processed')
  assert_equal(1, queue_size(queue), 'the message must still be in the queue')

  # --- object responding to parse ---
  boot_file = write_worker(dir, 'JsonParserWorker', queue, 'JSON', marker)

  status, output = run_shoryuken_until('-C', config_file, '-r', boot_file) { File.exist?(marker) }

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
  assert_equal({ 'id' => 1 }.inspect, File.read(marker))
end
