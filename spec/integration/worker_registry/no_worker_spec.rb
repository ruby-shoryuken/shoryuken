# frozen_string_literal: true

# This spec tests `shoryuken start` with a configured queue that has no worker.
#
# At start the process logs `No worker supplied for <queue>` and keeps running.
# A message on that queue logs `No worker found for <queue>` (it does not reach
# the exception handlers) and is not deleted, so it comes back after the
# visibility timeout, while the other queue's worker keeps processing.

def write_files(dir, worked_queue, idle_queue, marker)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class NoWorkerSpecWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{worked_queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY

  config_file = File.join(dir, 'shoryuken.yml')
  File.write(config_file, <<~YAML)
    queues:
      - #{worked_queue}
      - #{idle_queue}
  YAML

  [boot_file, config_file]
end

setup_sqs

attributes = { 'VisibilityTimeout' => '2' }

with_queue_and_dir(attributes: attributes) do |worked_queue, dir|
  with_queue_and_dir(attributes: attributes) do |idle_queue, _|
    marker = File.join(dir, 'processed')
    boot_file, config_file = write_files(dir, worked_queue, idle_queue, marker)

    Shoryuken::Client.queues(idle_queue).send_message(message_body: 'nobody handles this')
    Shoryuken::Client.queues(worked_queue).send_message(message_body: 'handled')

    status, output = run_shoryuken_until('-C', config_file, '-r', boot_file) do |log|
      File.exist?(marker) && log.scan("No worker found for #{idle_queue}").size >= 2
    end

    assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
    assert_includes(output, "No worker supplied for #{idle_queue}", "got: #{output}")
    refute(output.include?("No worker supplied for #{worked_queue}"), "got: #{output}")
    refute(output.include?('Processor failed'), "a missing worker must not raise, got: #{output}")
    assert_equal(1, queue_size(idle_queue), 'the message must not be deleted')
    assert_equal(0, queue_size(worked_queue), 'the other queue must still be processed')
  end
end
