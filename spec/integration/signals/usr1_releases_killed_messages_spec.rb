# frozen_string_literal: true

# This spec tests that USR1 releases the messages of workers it kills at `timeout`, for single and batch workers.
#
# A soft shutdown waits up to `timeout` for busy workers, then kills them. Their messages are not deleted and are
# visible again right after the exit, long before the queue's visibility timeout.
#
# It used to leave them in flight for the whole visibility timeout.

def write_stuck_worker(dir, queue, batch)
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class StuckWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true, batch: #{batch}

      def perform(_sqs_msg, _body)
        File.write(File.join('#{dir}', 'started'), '')
        sleep 60
      end
    end
  RUBY
  boot_file
end

setup_sqs

[false, true].each do |batch|
  with_queue_and_dir(attributes: { 'VisibilityTimeout' => '60' }) do |queue, dir|
    boot_file = write_stuck_worker(dir, queue, batch)

    bodies = Array.new(batch ? 3 : 1) { |i| "message-#{i}" }
    Shoryuken::Client.queues(queue).send_messages(bodies.map { |body| { message_body: body } })

    status, output = run_shoryuken_until('-q', queue, '-c', '2', '-t', '2', '-r', boot_file, signal: 'USR1') do
      File.exist?(File.join(dir, 'started'))
    end

    assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
    assert_includes(output, 'Received USR1, will soft shutdown', "got: #{output}")

    counts = queue_counts(queue)
    assert_equal(0, counts[:in_flight], "batch: #{batch}, the killed workers' messages must not stay in flight")
    assert_equal(bodies.size, counts[:visible], "batch: #{batch}, the killed workers' messages must be visible again")
  end
end
