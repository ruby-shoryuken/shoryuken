# frozen_string_literal: true

# This spec tests that a fetched message whose worker post is rejected by the
# executor is released (visibility timeout 0) instead of being left in flight.
#
# When the launcher executor rejects the worker post (it was shut down between
# the running? check and the post, or a bounded custom launcher_executor is
# saturated), Manager#assign rolls back its busy counter and skips the message.
# It used to just drop the message, so it stayed invisible on SQS for the whole
# queue visibility timeout before any consumer could receive it.
#
# Expected behavior: the rejected message is made visible again at once, and it
# is never processed.
#
# Regression: the message stayed in flight for the full visibility timeout.

require 'timeout'

setup_sqs

DT.clear

# Accepts the dispatch loop's posts but rejects every worker post (those come
# from Manager#assign), so each fetched message hits the rejection path.
rejecting_executor_class = Class.new(Concurrent::CachedThreadPool) do
  def post(*args, &block)
    if caller.any? { |line| line.include?('Manager#assign') }
      DT[:rejected] << true
      raise Concurrent::RejectedExecutionError
    end

    super
  end
end

executor = rejecting_executor_class.new(auto_terminate: true)
Shoryuken.define_singleton_method(:launcher_executor) { executor }

queue_name = DT.queue
# Far longer than the spec runs, so the message can only reappear if released.
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '60' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(sqs_msg, _body)
    DT[:processed] << sqs_msg.message_id
  end
end

worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'rejected post')

launcher = Shoryuken::Launcher.new
launcher.start

# This executor rejects every worker post, so each rejection releases the message
# and the next poll fetches it again. Stop after the first one to end that loop.
Timeout.timeout(15) { sleep 0.05 until DT[:rejected].size >= 1 }
Timeout.timeout(20) { launcher.stop! }

received = Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 3).messages

assert_equal(
  1,
  received.size,
  'a message whose worker post was rejected must be released at once, not stay in flight for the visibility timeout'
)
assert_equal('rejected post', received.first.body)
assert(DT[:processed].empty?, 'a message whose worker post was rejected must not be processed')
