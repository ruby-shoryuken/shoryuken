# frozen_string_literal: true

# This spec tests that a queue that does not exist raises Shoryuken::Errors::QueueNotFoundError naming the queue at
# runtime, when SQS reports it as QueueDoesNotExist (the current SQS JSON protocol and ElasticMQ do): on
# Shoryuken::Client.queues, on a raw worker perform_async with queue:, on an ActiveJob perform_later and for a queue
# given by a URL.
#
# It used to raise the raw Aws::SQS::Errors::QueueDoesNotExist; only NonExistentQueue was mapped.

setup_sqs
setup_active_job

WORKER_QUEUE = DT.queues[0]
JOB_QUEUE = DT.queues[1]

class MissingQueueWorker
  include Shoryuken::Worker

  shoryuken_options queue: WORKER_QUEUE

  def perform(_sqs_msg, _body); end
end

class MissingQueueJob < ActiveJob::Base
  queue_as JOB_QUEUE

  def perform; end
end

def assert_queue_not_found(name, label, &block)
  error = raised_error(StandardError, &block)

  assert_equal(Shoryuken::Errors::QueueNotFoundError, error.class, "#{label}: got #{error.inspect}")
  assert_equal("The specified queue #{name} does not exist.", error.message, "#{label}: got #{error.message}")
end

client_queue, url_queue = DT.uuids(2)

assert_queue_not_found(client_queue, 'Client.queues') do
  Shoryuken::Client.queues(client_queue)
end

assert_queue_not_found(WORKER_QUEUE, 'perform_async') do
  MissingQueueWorker.perform_async('body', queue: WORKER_QUEUE)
end

assert_queue_not_found(JOB_QUEUE, 'perform_later') do
  MissingQueueJob.perform_later
end

missing_url = "http://localhost:9324/000000000000/#{url_queue}"
assert_queue_not_found(missing_url, 'queue URL') do
  Shoryuken::Client.queues(missing_url)
end
