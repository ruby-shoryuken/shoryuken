# frozen_string_literal: true

# This spec tests that a USR1 soft shutdown of `shoryuken start` keeps extending the visibility of a long job that runs
# with `auto_visibility_timeout`.
#
# The soft shutdown waits for the job, which runs longer than the queue's visibility timeout. While it waits,
# the message stays invisible to other consumers, so it is processed exactly once and then deleted.
#
# Regression: #636 - USR1 and TSTP shut down the executor that ran the visibility timers, so the message became
# visible again during the stop and was processed a second time.

def write_long_job_worker(dir, queue, started, performed)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class LongVisibilityWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true, auto_visibility_timeout: true

      def perform(_sqs_msg, body)
        File.write('#{started}', '')
        sleep 15
        File.write('#{performed}', "\#{body}\\n", mode: 'a')
      end
    end
  RUBY
  boot_file
end

def start_redelivery_poller(queue_url, redelivered)
  Thread.new do
    until Thread.current[:stop]
      messages = Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 1).messages
      redelivered.concat(messages.map(&:body))
    end
  end
end

setup_sqs

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '6' }) do |queue, dir|
  started = File.join(dir, 'started')
  performed = File.join(dir, 'performed')
  boot_file = write_long_job_worker(dir, queue, started, performed)

  Shoryuken::Client.queues(queue).send_message(message_body: 'long job')
  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url

  # A second consumer: any message it receives while shoryuken still runs the job was redelivered
  redelivered = []
  poller = nil

  status, output = run_shoryuken_until('-q', queue, '-t', '30', '-r', boot_file, signal: 'USR1', timeout: 60) do
    File.exist?(started) && (poller ||= start_redelivery_poller(queue_url, redelivered))
  end

  poller[:stop] = true
  poller.join

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received USR1, will soft shutdown', "got: #{output}")
  assert_equal(['long job'], File.readlines(performed, chomp: true), "the job must finish once, got: #{output}")
  assert_equal([], redelivered, 'the message must stay invisible while the soft shutdown waits for the job')
  assert_equal(0, queue_size(queue), 'the message must be deleted after the job')
end
