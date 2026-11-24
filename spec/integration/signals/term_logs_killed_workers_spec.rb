# frozen_string_literal: true

# This spec tests that a shutdown that kills busy workers at `timeout` warns how
# many it kills, so an operator sees that jobs were cut off.
#
# A killed worker raises nothing, so its job logs neither "completed in" nor
# "failed in". It used to log only "Received TERM, will shutdown" and
# "Shutting down" and exit 0. A worker that finishes within `timeout` logs no
# warning.

def write_workers(dir, queue, started)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class KilledAtTimeoutWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(sqs_msg, body)
        File.write(File.join('#{started}', sqs_msg.message_id), '')
        sleep(body == 'fast' ? 0 : 60)
      end
    end
  RUBY
  boot_file
end

def started_count(started)
  Dir.children(started).size
end

setup_sqs

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '30' }) do |queue, dir|
  started = File.join(dir, 'started')
  Dir.mkdir(started)
  boot_file = write_workers(dir, queue, started)

  2.times { Shoryuken::Client.queues(queue).send_message(message_body: 'slow') }

  status, output = run_shoryuken_until('-q', queue, '-c', '3', '-t', '2', '-r', boot_file, signal: 'TERM') do
    started_count(started) == 2
  end

  assert(status.success?, "the process must still exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(
    output,
    'WARN: Killing 2 busy workers after the 2s shutdown timeout; ' \
    'their messages come back after the visibility timeout',
    "got: #{output}"
  )
end

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '30' }) do |queue, dir|
  started = File.join(dir, 'started')
  Dir.mkdir(started)
  boot_file = write_workers(dir, queue, started)

  Shoryuken::Client.queues(queue).send_message(message_body: 'fast')

  status, output = run_shoryuken_until('-q', queue, '-t', '2', '-r', boot_file, signal: 'TERM') do |log|
    log.include?('completed in: ')
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  refute(output.include?('Killing'), "no worker is busy, so none is killed: #{output}")
end
