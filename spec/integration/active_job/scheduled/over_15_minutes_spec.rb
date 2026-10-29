# frozen_string_literal: true

# This spec tests ActiveJob `set(wait:)` and `Shoryuken::Worker.perform_in`
# with a delay over the 15 minute SQS maximum.
#
# Expected behavior: both raise `Shoryuken::Errors::InvalidDelayError` before
# anything is sent, so the queue stays empty.

setup_sqs
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name)

class OverFifteenMinutesJob < ActiveJob::Base
  def perform; end
end

class OverFifteenMinutesWorker
  include Shoryuken::Worker

  def perform(sqs_msg, body); end
end

OverFifteenMinutesWorker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, OverFifteenMinutesWorker)

def delay_error(&block)
  block.call
  nil
rescue Shoryuken::Errors::InvalidDelayError => e
  e
end

job_error = delay_error { OverFifteenMinutesJob.set(queue: queue_name, wait: 16.minutes).perform_later }
worker_error = delay_error { OverFifteenMinutesWorker.perform_in(16 * 60, 'body') }

assert(job_error, 'set(wait: 16.minutes) should raise InvalidDelayError')
assert(worker_error, 'perform_in(16 * 60) should raise InvalidDelayError')
assert_equal('The maximum allowed delay is 15 minutes', job_error.message)
assert_equal('The maximum allowed delay is 15 minutes', worker_error.message)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
attributes = Shoryuken::Client.sqs.get_queue_attributes(
  queue_url: queue_url,
  attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed]
).attributes

assert_equal(0, attributes.values.sum(&:to_i), "Nothing should be sent, got #{attributes}")

delete_test_queue(queue_name)
