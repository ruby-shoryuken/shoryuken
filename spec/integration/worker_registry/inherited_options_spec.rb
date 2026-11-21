# frozen_string_literal: true

# This spec tests that a worker subclass inherits its parent's shoryuken_options.
#
# The parent sets queue, body_parser and auto_delete. The subclass sets only its
# own queue. It keeps the parent's JSON body parser and auto_delete, so it gets a
# Hash body and its message is deleted. The parent keeps its own queue, and each
# worker is registered on its own queue.
#
# Regression: #450 - a worker subclass did not inherit its parent's options.

require 'timeout'

setup_sqs

PARENT_QUEUE = DT.queues[0]
CHILD_QUEUE = DT.queues[1]

[PARENT_QUEUE, CHILD_QUEUE].each { |queue| create_test_queue(queue) }

Shoryuken.add_group('default', 2)
[PARENT_QUEUE, CHILD_QUEUE].each { |queue| Shoryuken.add_queue(queue, 1, 'default') }

class InheritedOptionsParentWorker
  include Shoryuken::Worker

  shoryuken_options queue: PARENT_QUEUE, body_parser: :json, auto_delete: true

  def perform(sqs_msg, body)
    DT[:processed] << [self.class.name, sqs_msg.queue_name, body]
  end
end

class InheritedOptionsChildWorker < InheritedOptionsParentWorker
  shoryuken_options queue: CHILD_QUEUE
end

assert_equal(PARENT_QUEUE, InheritedOptionsParentWorker.get_shoryuken_options['queue'])
assert_equal(CHILD_QUEUE, InheritedOptionsChildWorker.get_shoryuken_options['queue'])
assert_equal(:json, InheritedOptionsChildWorker.get_shoryuken_options['body_parser'])
assert(InheritedOptionsChildWorker.auto_delete?, 'The subclass should inherit auto_delete')
assert_equal([InheritedOptionsParentWorker], Shoryuken.worker_registry.workers(PARENT_QUEUE))
assert_equal([InheritedOptionsChildWorker], Shoryuken.worker_registry.workers(CHILD_QUEUE))

InheritedOptionsParentWorker.perform_async('from' => 'parent')
InheritedOptionsChildWorker.perform_async('from' => 'child')

launcher = Shoryuken::Launcher.new
launcher.start

Timeout.timeout(15) { sleep 0.2 until DT[:processed].size >= 2 }

launcher.stop

assert_equal(
  [
    ['InheritedOptionsChildWorker', CHILD_QUEUE, { 'from' => 'child' }],
    ['InheritedOptionsParentWorker', PARENT_QUEUE, { 'from' => 'parent' }]
  ],
  DT[:processed].sort_by(&:first)
)
[PARENT_QUEUE, CHILD_QUEUE].each do |queue|
  assert_equal(0, queue_size(queue), "Message on #{queue} should be deleted")
  delete_test_queue(queue)
end
