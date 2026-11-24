# frozen_string_literal: true

# This spec tests that a worker with a prepended module keeps its shoryuken_options.
#
# The parent prepends a module that wraps perform and sets queue, body_parser and
# auto_delete. The subclass sets only its own queue and inherits the rest. Both
# workers get a Hash body through the prepended module, and their messages are
# deleted.

setup_sqs

PARENT_QUEUE = DT.queues[0]
CHILD_QUEUE = DT.queues[1]

[PARENT_QUEUE, CHILD_QUEUE].each { |queue| create_test_queue(queue) }

Shoryuken.add_group('default', 2)
[PARENT_QUEUE, CHILD_QUEUE].each { |queue| Shoryuken.add_queue(queue, 1, 'default') }

module PerformRecorder
  def perform(sqs_msg, body)
    DT[:wrapped] << self.class.name
    super
  end
end

class PrependedParentWorker
  include Shoryuken::Worker
  prepend PerformRecorder

  shoryuken_options queue: PARENT_QUEUE, body_parser: :json, auto_delete: true

  def perform(sqs_msg, body)
    DT[:processed] << [self.class.name, sqs_msg.queue_name, body]
  end
end

class PrependedChildWorker < PrependedParentWorker
  shoryuken_options queue: CHILD_QUEUE
end

assert_equal(PARENT_QUEUE, PrependedParentWorker.get_shoryuken_options['queue'])
assert_equal(CHILD_QUEUE, PrependedChildWorker.get_shoryuken_options['queue'])
assert_equal(:json, PrependedChildWorker.get_shoryuken_options['body_parser'])
assert(PrependedChildWorker.auto_delete?, 'The subclass should inherit auto_delete')
assert_equal([PrependedParentWorker], Shoryuken.worker_registry.workers(PARENT_QUEUE))
assert_equal([PrependedChildWorker], Shoryuken.worker_registry.workers(CHILD_QUEUE))

PrependedParentWorker.perform_async('from' => 'parent')
PrependedChildWorker.perform_async('from' => 'child')

poll_queues_until { DT[:processed].size >= 2 }

assert_equal(
  [
    ['PrependedChildWorker', CHILD_QUEUE, { 'from' => 'child' }],
    ['PrependedParentWorker', PARENT_QUEUE, { 'from' => 'parent' }]
  ],
  DT[:processed].sort_by(&:first)
)
assert_equal(%w[PrependedChildWorker PrependedParentWorker], DT[:wrapped].sort)
[PARENT_QUEUE, CHILD_QUEUE].each do |queue|
  assert_equal(0, queue_size(queue), "Message on #{queue} should be deleted")
  delete_test_queue(queue)
end
