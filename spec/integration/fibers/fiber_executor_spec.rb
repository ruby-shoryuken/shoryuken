# frozen_string_literal: true

# This spec tests the fiber executor set with `executor: fiber` in the options. Each message runs as an Async task
# with a Fiber scheduler set in `perform`, all on one thread, and no more than the group's concurrency run at once.

require 'async'

CONCURRENCY = 3
MESSAGES = 9
RUNNING = Shoryuken::Helpers::AtomicCounter.new(0)

setup_sqs

class FiberWorker
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    DT[:peaks] << RUNNING.increment
    sleep(0.3)
    RUNNING.decrement

    DT[:jobs] << { body: body, scheduler: Fiber.scheduler, thread: Thread.current.object_id }
  end
end

with_queue_and_dir do |queue, _dir|
  Shoryuken::EnvironmentLoader.setup_options(executor: 'fiber', concurrency: CONCURRENCY, queues: [[queue, 1]]).load

  FiberWorker.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, FiberWorker)

  MESSAGES.times { |i| FiberWorker.perform_async(i.to_s) }

  poll_queues_until(timeout: 30) { DT[:jobs].size >= MESSAGES }

  assert_equal(:fiber, Shoryuken.executor)
  assert_equal((0...MESSAGES).map(&:to_s), DT[:jobs].map { |job| job[:body] }.sort)
  DT[:jobs].each { |job| assert(job[:scheduler].is_a?(Async::Scheduler), job[:scheduler].inspect) }
  assert_equal(1, DT[:jobs].map { |job| job[:thread] }.uniq.size, 'all messages must run on one thread')
  assert(DT[:peaks].max <= CONCURRENCY, "at most #{CONCURRENCY} messages may run at once, saw #{DT[:peaks].max}")
  assert(DT[:peaks].max > 1, 'messages must overlap')
  assert_equal(0, queue_size(queue))
end
