# frozen_string_literal: true

# This spec tests that a queue that does not exist raises Shoryuken::Errors::QueueNotFoundError naming the queue at
# runtime, when SQS reports it as QueueDoesNotExist (the current SQS JSON protocol and ElasticMQ do): on
# Shoryuken::Client.queues, on a raw worker perform_async with queue:, on an ActiveJob perform_later and for a queue
# given by a URL.
#
# It used to raise the raw Aws::SQS::Errors::QueueDoesNotExist; only NonExistentQueue was mapped.

setup_sqs
setup_active_job

MISSING_QUEUES = DT.uuids(4)

class MissingQueueWorker
  include Shoryuken::Worker

  shoryuken_options queue: MISSING_QUEUES[1]

  def perform(_sqs_msg, _body); end
end

class MissingQueueJob < ActiveJob::Base
  queue_as MISSING_QUEUES[2]

  def perform; end
end

def assert_queue_not_found(name, label, &block)
  error = raised_error(StandardError, &block)

  assert_equal(Shoryuken::Errors::QueueNotFoundError, error.class, "#{label}: got #{error.inspect}")
  assert_equal("The specified queue #{name} does not exist.", error.message, "#{label}: got #{error.message}")
end

assert_queue_not_found(MISSING_QUEUES[0], 'Client.queues') do
  Shoryuken::Client.queues(MISSING_QUEUES[0])
end

assert_queue_not_found(MISSING_QUEUES[1], 'perform_async') do
  MissingQueueWorker.perform_async('body', queue: MISSING_QUEUES[1])
end

assert_queue_not_found(MISSING_QUEUES[2], 'perform_later') do
  MissingQueueJob.perform_later
end

missing_url = "http://localhost:9324/000000000000/#{MISSING_QUEUES[3]}"
assert_queue_not_found(missing_url, 'queue URL') do
  Shoryuken::Client.queues(missing_url)
end
