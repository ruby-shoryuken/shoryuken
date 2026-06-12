# frozen_string_literal: true

# This spec tests the interplay between non_retryable_exceptions and
# retry_intervals (exponential backoff) when both are configured on the
# same worker.
#
# Expected behavior: non_retryable_exceptions takes precedence - a message
# raising a non-retryable exception must be deleted immediately and never
# retried, while other exceptions still go through the backoff schedule.
#
# Regression: ExponentialBackoffRetry sits inside NonRetryableException in
# the default middleware chain and used to swallow every exception after
# scheduling a retry, so NonRetryableException never saw non-retryable
# errors and the message was retried (with the last interval repeated)
# instead of being deleted.

require 'timeout'

setup_sqs

DT.clear

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Exception classes for testing
PermanentValidationError = Class.new(StandardError)
TransientNetworkError = Class.new(StandardError)

# Worker with BOTH retry_intervals and non_retryable_exceptions configured
combined_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true,
                    batch: false,
                    retry_intervals: [1, 1],
                    non_retryable_exceptions: [PermanentValidationError]

  def perform(sqs_msg, body)
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    DT[:attempts] << { receive_count: receive_count, body: body, time: Time.now }

    case body
    when 'non_retryable'
      raise PermanentValidationError, 'Permanently invalid input'
    when 'retryable'
      # Fail on first 2 attempts (covered by retry_intervals), succeed on 3rd
      raise TransientNetworkError, "Temporary failure on attempt #{receive_count}" if receive_count < 3

      DT[:successful_processing] << { body: body, final_receive_count: receive_count }
    end
  end
end

combined_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, combined_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

launcher = Shoryuken::Launcher.new
launcher.start

begin
  # Test 1: a non-retryable exception must win over the backoff schedule -
  # the message is attempted exactly once and deleted, never retried.
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: 'non_retryable'
  )

  Timeout.timeout(10) { sleep 0.5 until DT[:attempts].size >= 1 }

  # Give a buggy retry every chance to happen: with retry_intervals [1, 1]
  # a swallowed exception would bring the message back after ~1s.
  sleep 5

  non_retryable_attempts = DT[:attempts].select { |a| a[:body] == 'non_retryable' }
  assert_equal(
    1,
    non_retryable_attempts.size,
    'Non-retryable exception must not be retried even when retry_intervals is configured ' \
    "(got #{non_retryable_attempts.size} attempts)"
  )

  attributes = Shoryuken::Client.sqs.get_queue_attributes(
    queue_url: queue_url,
    attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
  ).attributes

  total_messages = attributes['ApproximateNumberOfMessages'].to_i +
                   attributes['ApproximateNumberOfMessagesNotVisible'].to_i
  assert_equal(
    0,
    total_messages,
    'Message with non-retryable exception must be deleted immediately, not scheduled for retry'
  )

  # Test 2: exceptions NOT in the non-retryable list still follow the
  # backoff schedule and eventually succeed.
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: 'retryable'
  )

  Timeout.timeout(20) { sleep 0.5 until DT[:successful_processing].size >= 1 }

  retryable_attempts = DT[:attempts].select { |a| a[:body] == 'retryable' }
  assert(retryable_attempts.size >= 3, 'Retryable exception should still go through the backoff schedule')
  assert_equal('retryable', DT[:successful_processing].first[:body])
  assert_equal(3, DT[:successful_processing].first[:final_receive_count])
ensure
  launcher.stop
end
