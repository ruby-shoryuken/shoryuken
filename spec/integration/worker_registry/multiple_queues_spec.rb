# frozen_string_literal: true

# This spec tests workers whose `queue` option is an Array or a lambda.
#
# A worker with `queue: [q1, q2]` is registered for both queues and processes
# messages from each; `sqs_msg.queue_name` tells them apart. `perform_async`
# with `queue:` sends to that queue only. `perform_async`, `perform_in` and
# `perform_at` without `queue:` raise an ArgumentError naming the worker and its
# queues, for an Array and for a lambda that returns several queues, and send
# nothing. A lambda that returns one queue name registers and processes on it.
#
# It used to raise `NoMethodError: undefined method 'start_with?'` for an
# instance of Array when sending without `queue:`.

require 'timeout'

setup_sqs

DT.clear

prefix = DT.uuid
first_queue, second_queue = DT.uuids(2)
computed_queue = "#{prefix}-q"
[first_queue, second_queue, computed_queue].each { |queue| create_test_queue(queue) }

Shoryuken.add_group('default', 2)
[first_queue, second_queue, computed_queue].each { |queue| Shoryuken.add_queue(queue, 1, 'default') }

MultipleQueuesWorker = Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: [first_queue, second_queue], auto_delete: true

  def perform(sqs_msg, body)
    DT[:processed] << [sqs_msg.queue_name, body]
  end
end

ComputedQueueWorker = Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: -> { "#{prefix}-q" }, auto_delete: true

  def perform(sqs_msg, body)
    DT[:processed] << [sqs_msg.queue_name, body]
  end
end

ComputedQueuesWorker = Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: -> { ["#{prefix}-a", "#{prefix}-b"] }

  def perform(_sqs_msg, _body); end
end

assert_equal([MultipleQueuesWorker], Shoryuken.worker_registry.workers(first_queue))
assert_equal([MultipleQueuesWorker], Shoryuken.worker_registry.workers(second_queue))
assert_equal([ComputedQueueWorker], Shoryuken.worker_registry.workers(computed_queue))

async_error = raised_error(ArgumentError) { MultipleQueuesWorker.perform_async('no queue') }
perform_in_error = raised_error(ArgumentError) { MultipleQueuesWorker.perform_in(5, 'no queue') }
perform_at_error = raised_error(ArgumentError) { MultipleQueuesWorker.perform_at(Time.now + 5, 'no queue') }
computed_error = raised_error(ArgumentError) { ComputedQueuesWorker.perform_async('no queue') }

assert(async_error, 'perform_async without queue: should raise ArgumentError')
assert(perform_in_error, 'perform_in without queue: should raise ArgumentError')
assert(perform_at_error, 'perform_at without queue: should raise ArgumentError')
assert(computed_error, 'perform_async without queue: should raise ArgumentError for a lambda with several queues')
assert_equal(
  "MultipleQueuesWorker has several queues (#{first_queue}, #{second_queue}): pass the queue: option to choose one",
  async_error.message
)
assert_includes(computed_error.message, "ComputedQueuesWorker has several queues (#{prefix}-a, #{prefix}-b)")
assert_equal(0, queue_size(first_queue, delayed: true), 'Nothing should be sent')
assert_equal(0, queue_size(second_queue, delayed: true), 'Nothing should be sent')

MultipleQueuesWorker.perform_async('first', queue: first_queue)
MultipleQueuesWorker.perform_async('second', queue: second_queue)
ComputedQueueWorker.perform_async('computed')

assert_equal(1, queue_size(first_queue))
assert_equal(1, queue_size(second_queue))
assert_equal(1, queue_size(computed_queue))

launcher = Shoryuken::Launcher.new
launcher.start

Timeout.timeout(15) { sleep 0.2 until DT[:processed].size >= 3 }

launcher.stop

assert_equal(
  [[computed_queue, 'computed'], [first_queue, 'first'], [second_queue, 'second']].sort,
  DT[:processed].sort
)
[first_queue, second_queue, computed_queue].each do |queue|
  assert_equal(0, queue_size(queue))
  delete_test_queue(queue)
end
