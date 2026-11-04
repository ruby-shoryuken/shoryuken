# frozen_string_literal: true

# This spec tests sending messages from concurrent Async tasks: `send_message`
# on a queue, `perform_async` and `perform_in` on a worker. Every message is
# sent once and processed.

require 'async'

setup_sqs

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    DT[:bodies] << body
  end
end

with_queue_and_dir do |queue, _dir|
  Shoryuken.add_group('default', 2)
  Shoryuken.add_queue(queue, 1, 'default')

  worker.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker)

  sqs_queue = Shoryuken::Client.queues(queue)

  Sync do |task|
    tasks = Array.new(5) do |i|
      [
        task.async { sqs_queue.send_message(message_body: "send-#{i}") },
        task.async { worker.perform_async("async-#{i}") },
        task.async { worker.perform_in(1, "in-#{i}") }
      ]
    end

    tasks.flatten.each(&:wait)
  end

  expected = %w[send async in].flat_map { |kind| Array.new(5) { |i| "#{kind}-#{i}" } }

  poll_queues_until(timeout: 20) { DT[:bodies].size >= expected.size }

  assert_equal(expected.sort, DT[:bodies].sort)
  assert_equal(0, queue_size(queue))
end
