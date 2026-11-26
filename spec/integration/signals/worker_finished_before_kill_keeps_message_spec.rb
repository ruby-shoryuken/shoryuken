# frozen_string_literal: true

# This spec tests that a shutdown releases only the messages of workers it killed, not of workers that finished their
# job between the in-flight snapshot and the kill.
#
# The boot file widens that window with a sleep before the kill. A job that finished and deleted its message must not
# give a "Failed to release" error, and a job that failed with a backoff visibility must keep that visibility.

def write_worker(dir, queue, mode)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    module SlowKill
      def log_killed_workers
        sleep 1.5
        super
      end
    end

    Shoryuken::Launcher.prepend(SlowKill)

    class FinishingWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(sqs_msg, _body)
        File.write(File.join('#{dir}', 'started'), '')
        sleep 2.5
        return if #{mode == :delete}

        sqs_msg.change_visibility(visibility_timeout: 50)
        raise 'job failed'
      end
    end
  RUBY
  boot_file
end

def receive_after_exit(queue)
  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 3).messages.map(&:body)
end

def run_until_started(queue, dir, boot_file)
  run_shoryuken_until('-q', queue, '-t', '2', '-r', boot_file, signal: 'TERM') do
    File.exist?(File.join(dir, 'started'))
  end
end

setup_sqs

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
  boot_file = write_worker(dir, queue, :delete)
  Shoryuken::Client.queues(queue).send_message(message_body: 'finished')

  status, output = run_until_started(queue, dir, boot_file)

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_equal(0, queue_size(queue), "the finished job must delete its message: #{output}")
  refute(output.include?('Failed to release'), "a deleted message must not be released: #{output}")
end

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
  boot_file = write_worker(dir, queue, :backoff)
  Shoryuken::Client.queues(queue).send_message(message_body: 'backoff')

  status, output = run_until_started(queue, dir, boot_file)

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'job failed', "got: #{output}")
  assert_equal([], receive_after_exit(queue), "the job's backoff visibility must hold: #{output}")
end
