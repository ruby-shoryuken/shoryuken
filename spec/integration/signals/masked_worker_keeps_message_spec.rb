# frozen_string_literal: true

# This spec tests that a shutdown does not release the message of a worker that keeps running after the kill.
#
# `Thread#kill` only asks a thread to stop: a worker that masks interrupts runs on. Its message stays in flight while
# it runs, so no other consumer receives it, and the shutdown logs that it stays in flight. Covered for TERM, which
# exits, and for TSTP, which stops processing and keeps the process running.

def write_masked_worker(dir, queue)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class MaskedWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write(File.join('#{dir}', 'started'), '')
        Thread.handle_interrupt(Object => :never) { sleep 8 }
      end
    end

    Shoryuken.on(:stopped) { Shoryuken.logger.info('lifecycle event: stopped') }
  RUBY
  boot_file
end

def receive_while_running(queue)
  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 2).messages.map(&:body)
end

setup_sqs

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
  boot_file = write_masked_worker(dir, queue)
  Shoryuken::Client.queues(queue).send_message(message_body: 'masked')

  receiver = nil
  status, output = run_shoryuken_until('-q', queue, '-t', '1', '-r', boot_file, signal: 'TERM') do
    next false unless File.exist?(File.join(dir, 'started'))

    # Past the 1 s timeout and the wait for killed workers, while the masked section still runs
    receiver ||= Thread.new do
      sleep 2.5
      receive_while_running(queue)
    end
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_equal([], receiver.value, "TERM: the running worker's message must stay in flight: #{output}")
  assert_includes(output, '1 message(s) of killed workers still running in group default', "got: #{output}")
end

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
  boot_file = write_masked_worker(dir, queue)
  Shoryuken::Client.queues(queue).send_message(message_body: 'masked')

  tstp_sent = false
  received = nil
  status, output = run_shoryuken_until('-q', queue, '-t', '1', '-r', boot_file, signal: 'TERM') do |log, pid|
    tstp_sent ||= File.exist?(File.join(dir, 'started')) && Process.kill('TSTP', pid)
    next false unless log.include?('lifecycle event: stopped')

    received ||= receive_while_running(queue)
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received TSTP, will stop accepting new work', "got: #{output}")
  assert_equal([], received, "TSTP: the running worker's message must stay in flight: #{output}")
  assert_includes(output, '1 message(s) of killed workers still running in group default', "got: #{output}")
end
