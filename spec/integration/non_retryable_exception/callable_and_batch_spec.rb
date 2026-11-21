# frozen_string_literal: true

# This spec tests non_retryable_exceptions given as a callable and on a batch
# worker. A callable receives the exception and decides: a truthy result
# deletes the message at once, a falsy one lets it be retried. On a batch
# worker a non-retryable exception deletes every message of the batch.

require 'timeout'

setup_sqs

DT.clear

CALLABLE_QUEUE = DT.queue
BATCH_QUEUE = "#{DT.queue}-batch".freeze
create_test_queue(CALLABLE_QUEUE, attributes: { 'VisibilityTimeout' => '1' })
create_test_queue(BATCH_QUEUE, attributes: { 'VisibilityTimeout' => '1' })
Shoryuken.add_group('default', 2)
Shoryuken.add_queue(CALLABLE_QUEUE, 1, 'default')
Shoryuken.add_queue(BATCH_QUEUE, 1, 'default')

BatchPermanentError = Class.new(StandardError)

class CallableNonRetryableWorker
  include Shoryuken::Worker

  shoryuken_options(
    queue: CALLABLE_QUEUE,
    auto_delete: true,
    batch: false,
    non_retryable_exceptions: ->(error) { error.message.include?('permanent') }
  )

  def perform(sqs_msg, body)
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    DT[:callable_attempts] << { body: body, receive_count: receive_count }

    case body
    when 'permanent'
      raise StandardError, 'permanent failure'
    when 'transient'
      raise StandardError, 'temporary failure' if receive_count < 2

      DT[:callable_successes] << body
    end
  end
end

class BatchNonRetryableWorker
  include Shoryuken::Worker

  shoryuken_options(
    queue: BATCH_QUEUE,
    auto_delete: false,
    batch: true,
    non_retryable_exceptions: [BatchPermanentError]
  )

  def perform(_sqs_msgs, bodies)
    DT[:batches] << Array(bodies)

    raise BatchPermanentError, 'permanently invalid batch'
  end
end

batch_bodies = 5.times.map { |i| "batch-#{i}" }
Shoryuken::Client.queues(BATCH_QUEUE).send_messages(
  entries: batch_bodies.map { |body| { id: SecureRandom.uuid, message_body: body } }
)

callable_url = Shoryuken::Client.sqs.get_queue_url(queue_name: CALLABLE_QUEUE).queue_url
Shoryuken::Client.sqs.send_message(queue_url: callable_url, message_body: 'permanent')
Shoryuken::Client.sqs.send_message(queue_url: callable_url, message_body: 'transient')

launcher = Shoryuken::Launcher.new
launcher.start

begin
  Timeout.timeout(20) do
    sleep 0.5 until DT[:callable_successes].size >= 1 && DT[:batches].flatten.size >= batch_bodies.size
  end

  # With VisibilityTimeout 1, a message that was not deleted comes back within this window
  sleep 4

  permanent_attempts = DT[:callable_attempts].select { |a| a[:body] == 'permanent' }
  assert_equal(1, permanent_attempts.size, 'A truthy callable result must delete the message at once')

  transient_attempts = DT[:callable_attempts].select { |a| a[:body] == 'transient' }
  assert_equal([1, 2], transient_attempts.map { |a| a[:receive_count] }, 'A falsy callable result must retry')
  assert_equal(['transient'], DT[:callable_successes])
  assert_equal(0, queue_size(CALLABLE_QUEUE))

  received = DT[:batches].flatten
  assert(DT[:batches].any? { |batch| batch.size > 1 }, "Expected a batch with several messages: #{DT[:batches]}")
  assert_equal(batch_bodies.sort, received.sort, 'Every batch message must be received exactly once')
  assert_equal(0, queue_size(BATCH_QUEUE))
ensure
  Timeout.timeout(30) { launcher.stop }
end
