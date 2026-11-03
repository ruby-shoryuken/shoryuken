# frozen_string_literal: true

# This spec tests that the inline executor runs a worker that never calls shoryuken_options.
#
# It used to raise NoMethodError, because the executor read the worker's own options hash, which is nil
# until shoryuken_options is called. The worker now uses Shoryuken.default_worker_options, so `batch`
# set only there gives the batch call shape.

sqs_client = Aws::SQS::Client.new(stub_responses: true)
Shoryuken.sqs_client = sqs_client
Shoryuken.worker_executor = Shoryuken::Worker::InlineExecutor

class NoOptionsWorker
  include Shoryuken::Worker

  def perform(sqs_msg, body)
    DT[:perform] << [sqs_msg, body]
  end
end

NoOptionsWorker.perform_async('single')

sqs_msg, body = DT[:perform].last
assert_equal(Shoryuken::InlineMessage, sqs_msg.class)
assert_equal('default', sqs_msg.queue_name)
assert_equal('single', body)

Shoryuken.default_worker_options['batch'] = true

NoOptionsWorker.perform_async('batched')

sqs_msgs, bodies = DT[:perform].last
assert_equal([Shoryuken::InlineMessage], sqs_msgs.map(&:class))
assert_equal(['batched'], bodies)

assert_equal([], sqs_client.api_requests)
