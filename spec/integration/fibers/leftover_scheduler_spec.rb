# frozen_string_literal: true

# This spec tests that a job leaving a Fiber scheduler set on its thread does
# not break the next jobs on that thread. Shoryuken sets the scheduler of the
# thread back to the one before the job and logs a warning.
#
# It used to keep the scheduler: the next job calling Async's `Sync` with a
# blocking call waited forever on a scheduler that nothing ran.

require 'async'

setup_sqs

log = StringIO.new
Shoryuken.logger = Logger.new(log)
executor = Concurrent::FixedThreadPool.new(1)
Shoryuken.define_singleton_method(:launcher_executor) { executor }

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    if body == 'leave'
      Fiber.set_scheduler(Async::Scheduler.new)
    else
      Sync { sleep(0.05) }
    end

    DT[:jobs] << { body: body, thread: Thread.current.object_id }
  end
end

with_queue_and_dir(fifo: true) do |queue, _dir|
  Shoryuken.add_group('default', 1)
  Shoryuken.add_queue(queue, 1, 'default')

  worker.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker)

  %w[leave sync-1 sync-2].each do |body|
    worker.perform_async(body, message_group_id: 'scheduler')
  end

  poll_queues_until(timeout: 20) { DT[:jobs].size >= 3 }

  assert_equal(%w[leave sync-1 sync-2], DT[:jobs].map { |job| job[:body] })
  assert_equal(1, DT[:jobs].map { |job| job[:thread] }.uniq.size, 'all jobs must run on one thread')
  assert_includes(
    log.string,
    "A job on #{queue} left a Fiber scheduler set; Shoryuken set back the previous one after the job"
  )
  assert_equal(0, queue_size(queue))
end
