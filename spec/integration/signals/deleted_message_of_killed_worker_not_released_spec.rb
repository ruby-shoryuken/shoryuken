# frozen_string_literal: true

# This spec tests that a shutdown which kills a job that already deleted its message logs no release error.
#
# The job deletes its message first (`auto_delete: false`, `sqs_msg.delete`), then runs past the shutdown timeout and is
# killed. The release of the killed worker's message fails as the message is gone: that is not an error.

def write_worker(dir, queue)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class DeleteFirstWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: false

      def perform(sqs_msg, _body)
        sqs_msg.delete
        File.write(File.join('#{dir}', 'started'), '')
        sleep 30
      end
    end
  RUBY
  boot_file
end

setup_sqs

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
  boot_file = write_worker(dir, queue)
  Shoryuken::Client.queues(queue).send_message(message_body: 'deleted first')

  status, output = run_shoryuken_until('-q', queue, '-t', '1', '-r', boot_file, signal: 'TERM') do
    File.exist?(File.join(dir, 'started'))
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Killing 1 busy worker', "the job must be killed at the shutdown timeout: #{output}")
  assert_equal(0, queue_size(queue), "the job must have deleted its message: #{output}")
  refute(output.include?('Failed to release'), "a deleted message must not give a release error: #{output}")
end
