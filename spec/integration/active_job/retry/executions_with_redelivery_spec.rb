# frozen_string_literal: true

# This spec tests ActiveJob `executions` when a job is retried by `retry_on`
# and also redelivered by SQS.
#
# The job fails with a `retry_on` error twice, then with an
# error `retry_on` does not handle (SQS delivers the same message again), then
# with a `retry_on` error once more, then succeeds. `executions` keeps
# ActiveJob's count across `retry_on` retries and the redelivery adds one:
# 1, 2, 3, 4, 5. `exception_executions` counts only the `retry_on` errors.
#
# Regression: `executions` was replaced by the receive count minus one, so it
# read 1, 1, 1, 2, 1.

setup_sqs
setup_active_job

queue = DT.queue
create_test_queue(queue, attributes: { 'VisibilityTimeout' => '2' })

RetryableError = Class.new(StandardError)
OtherError = Class.new(StandardError)

class ExecutionsWithRedeliveryJob < ActiveJob::Base
  retry_on RetryableError, wait: 0, attempts: 5

  def perform
    DT[:executions] << [executions, exception_executions.values.sum]

    case DT[:executions].size
    when 1, 2, 4 then raise RetryableError
    when 3 then raise OtherError
    end
  end
end

Shoryuken.exception_handlers = [->(error, _queue, _sqs_msg) { DT[:unhandled] << error.class }]

ExecutionsWithRedeliveryJob.queue_as(queue)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue, 1, 'default')
Shoryuken.register_worker(queue, Shoryuken::ActiveJob::JobWrapper)

ExecutionsWithRedeliveryJob.perform_later

poll_queues_until(timeout: 30) { DT[:executions].size >= 5 && queue_size(queue).zero? }

assert_equal([OtherError], DT[:unhandled])
assert_equal([[1, 0], [2, 1], [3, 2], [4, 2], [5, 3]], DT[:executions])

delete_test_queue(queue)
