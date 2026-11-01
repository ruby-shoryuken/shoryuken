# frozen_string_literal: true

# This spec tests the documented contract of Shoryuken::Worker::InlineExecutor.
#
# Expected behavior:
# - perform_async calls perform right away and returns its result
# - Neither global nor worker server middleware runs
# - perform_in runs the job right away, ignoring the delay
# - No SQS request is made

sqs_client = Aws::SQS::Client.new(stub_responses: true)
Shoryuken.sqs_client = sqs_client
Shoryuken.worker_executor = Shoryuken::Worker::InlineExecutor

class GlobalRecordingMiddleware
  def call(_worker, _queue, _sqs_msg, _body)
    DT[:middleware] << :global
    yield
  end
end

class WorkerRecordingMiddleware
  def call(_worker, _queue, _sqs_msg, _body)
    DT[:middleware] << :worker
    yield
  end
end

Shoryuken.server_middleware do |chain|
  chain.add GlobalRecordingMiddleware
end

class InlineContractWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'inline-contract', auto_delete: true

  server_middleware do |chain|
    chain.add WorkerRecordingMiddleware
  end

  def perform(sqs_msg, body)
    DT[:perform] << [sqs_msg.class, sqs_msg.queue_name, body]
    "done-#{body}"
  end
end

assert_equal('done-now', InlineContractWorker.perform_async('now'))
assert_equal([[Shoryuken::InlineMessage, 'inline-contract', 'now']], DT[:perform])

delay = 60
started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
result = InlineContractWorker.perform_in(delay, 'later')
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

assert_equal('done-later', result)
assert_equal([Shoryuken::InlineMessage, 'inline-contract', 'later'], DT[:perform].last)
assert(elapsed < delay, "perform_in waited #{elapsed}s")

assert_equal([], DT[:middleware])
assert_equal([], sqs_client.api_requests)
