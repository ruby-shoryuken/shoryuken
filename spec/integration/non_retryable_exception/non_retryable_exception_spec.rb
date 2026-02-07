# frozen_string_literal: true

# This spec tests the non_retryable_exception middleware functionality.
# When non_retryable_exceptions is configured, messages that raise those exceptions
# should be deleted immediately instead of being retried.

require 'timeout'

setup_localstack

# Reset DT state to prevent data leakage from previous tests
DT.clear

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Define custom exception classes for testing
InvalidInputError = Class.new(StandardError)
RecordNotFoundError = Class.new(StandardError)
RetryableError = Class.new(StandardError)

# Worker that handles non-retryable exceptions
non_retryable_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: false,
                    batch: false,
                    non_retryable_exceptions: [InvalidInputError, RecordNotFoundError]

  def perform(sqs_msg, body)
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    DT[:attempts] << { receive_count: receive_count, body: body }

    case body
    when 'non_retryable_invalid'
      raise InvalidInputError, 'Invalid input data'
    when 'non_retryable_not_found'
      raise RecordNotFoundError, 'Record not found'
    when 'retryable_error'
      # Fail on first attempt, succeed on retry
      if receive_count < 2
        raise RetryableError, 'Temporary failure'
      end
      DT[:successful_processing] << { body: body, final_receive_count: receive_count }
      sqs_msg.delete
    when 'success'
      DT[:successful_processing] << { body: body, final_receive_count: receive_count }
      sqs_msg.delete
    end
  end
end

non_retryable_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, non_retryable_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Start launcher once for all tests
launcher = Shoryuken::Launcher.new
launcher.start

begin
  # Test 1: Non-retryable exception (InvalidInputError) should be deleted immediately
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: 'non_retryable_invalid'
  )

  # Wait for processing attempt
  Timeout.timeout(10) { sleep 0.5 until DT[:attempts].size >= 1 }

  # Verify it was only attempted once (not retried)
  invalid_attempts = DT[:attempts].select { |a| a[:body] == 'non_retryable_invalid' }
  assert_equal(1, invalid_attempts.size, 'Non-retryable exception should only be attempted once')
  assert_equal(1, invalid_attempts.first[:receive_count], 'Should be first attempt')

  # Wait a moment for deletion to complete
  sleep 2

  # Verify message was deleted - queue should be empty
  attributes = Shoryuken::Client.sqs.get_queue_attributes(
    queue_url: queue_url,
    attribute_names: ['ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesNotVisible']
  ).attributes

  total_messages = attributes['ApproximateNumberOfMessages'].to_i +
                   attributes['ApproximateNumberOfMessagesNotVisible'].to_i
  assert_equal(0, total_messages, 'Message with non-retryable exception should be deleted immediately')

  # Test 2: Another non-retryable exception (RecordNotFoundError) should also be deleted immediately
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: 'non_retryable_not_found'
  )

  # Wait for processing attempt
  Timeout.timeout(10) { sleep 0.5 until DT[:attempts].size >= 2 }

  # Verify it was only attempted once
  not_found_attempts = DT[:attempts].select { |a| a[:body] == 'non_retryable_not_found' }
  assert_equal(1, not_found_attempts.size, 'Non-retryable exception should only be attempted once')

  # Wait for deletion
  sleep 2

  # Verify queue is empty again
  attributes = Shoryuken::Client.sqs.get_queue_attributes(
    queue_url: queue_url,
    attribute_names: ['ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesNotVisible']
  ).attributes

  total_messages = attributes['ApproximateNumberOfMessages'].to_i +
                   attributes['ApproximateNumberOfMessagesNotVisible'].to_i
  assert_equal(0, total_messages, 'Message with non-retryable exception should be deleted immediately')

  # Test 3: Retryable exception (not in non_retryable_exceptions list) should still retry
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: 'retryable_error'
  )

  # Wait for successful processing (after retry)
  Timeout.timeout(15) { sleep 0.5 until DT[:successful_processing].size >= 1 }

  # Verify it was retried
  retryable_attempts = DT[:attempts].select { |a| a[:body] == 'retryable_error' }
  assert(retryable_attempts.size >= 2, 'Retryable exception should be retried')
  assert_equal(1, DT[:successful_processing].size, 'Message should eventually succeed after retry')
  assert_equal('retryable_error', DT[:successful_processing].first[:body])

  # Test 4: Successful message should process normally
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: 'success'
  )

  # Wait for successful processing
  Timeout.timeout(10) { sleep 0.5 until DT[:successful_processing].size >= 2 }

  # Verify successful processing
  success_attempts = DT[:attempts].select { |a| a[:body] == 'success' }
  assert_equal(1, success_attempts.size, 'Successful message should only be attempted once')
  assert_equal(2, DT[:successful_processing].size, 'Both successful messages should be processed')
ensure
  launcher.stop
end

