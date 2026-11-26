# frozen_string_literal: true

# This spec tests the inline executor with a worker whose `queue` option is an Array.
#
# `perform_async` and `perform_in` without `queue:` raise the same Shoryuken::Errors::QueueNotSpecifiedError as the
# default executor and do not run the job: several queues name the worker and its queues, an empty Array asks for
# `queue:`. With `queue:` the job runs with that `queue_name`; a one-element Array runs it with its only queue.
#
# It used to run the job with `sqs_msg.queue_name` set to the Array.

sqs_client = Aws::SQS::Client.new(stub_responses: true)
Shoryuken.sqs_client = sqs_client
Shoryuken.worker_executor = Shoryuken::Worker::InlineExecutor

FIRST_QUEUE = DT.queues[0]
SECOND_QUEUE = DT.queues[1]

class MultipleQueuesWorker
  include Shoryuken::Worker

  shoryuken_options queue: [FIRST_QUEUE, SECOND_QUEUE]

  def perform(sqs_msg, body)
    DT[:performed] << [sqs_msg.queue_name, body]
  end
end

class EmptyQueuesWorker
  include Shoryuken::Worker

  shoryuken_options queue: []

  def perform(sqs_msg, body)
    DT[:performed] << [sqs_msg.queue_name, body]
  end
end

class SingleQueueArrayWorker
  include Shoryuken::Worker

  shoryuken_options queue: [FIRST_QUEUE]

  def perform(sqs_msg, body)
    DT[:performed] << [sqs_msg.queue_name, body]
  end
end

async_error = raised_error(Shoryuken::Errors::QueueNotSpecifiedError) { MultipleQueuesWorker.perform_async('no queue') }
perform_in_error = raised_error(Shoryuken::Errors::QueueNotSpecifiedError) { MultipleQueuesWorker.perform_in(5, 'no queue') }
empty_error = raised_error(Shoryuken::Errors::QueueNotSpecifiedError) { EmptyQueuesWorker.perform_async('no queue') }

assert(async_error, 'perform_async without queue: should raise QueueNotSpecifiedError')
assert(perform_in_error, 'perform_in without queue: should raise QueueNotSpecifiedError')
assert(empty_error, 'perform_async without queue: should raise QueueNotSpecifiedError for an empty Array')
assert_equal(
  "MultipleQueuesWorker has several queues (#{FIRST_QUEUE}, #{SECOND_QUEUE}): pass the queue: option to choose one",
  async_error.message
)
assert_equal(async_error.message, perform_in_error.message)
assert_equal('EmptyQueuesWorker has no queue: pass the queue: option', empty_error.message)
assert_equal([], DT[:performed], 'No job should run')

MultipleQueuesWorker.perform_async('second', queue: SECOND_QUEUE)
SingleQueueArrayWorker.perform_async('single')

assert_equal([[SECOND_QUEUE, 'second'], [FIRST_QUEUE, 'single']], DT[:performed])
assert_equal([], sqs_client.api_requests)
