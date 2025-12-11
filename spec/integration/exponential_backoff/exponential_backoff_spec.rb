# frozen_string_literal: true

# This spec tests the exponential_backoff_retry middleware functionality.
# When retry_intervals is configured, failed jobs should have their visibility
# timeout adjusted based on the retry attempt number.

setup_localstack

queue_name = DT.queue

# Create queue with short visibility timeout
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Worker that fails on first attempts, succeeds after retry_intervals exhausted
backoff_worker = Class.new do
  include Shoryuken::Worker

  # Retry after 1 second, then 2 seconds
  shoryuken_options retry_intervals: [1, 2], auto_delete: true

  def perform(sqs_msg, body)
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    DT[:attempts] << { receive_count: receive_count, time: Time.now }

    # Fail on first 2 attempts, succeed on 3rd
    if receive_count < 3
      raise "Simulated failure on attempt #{receive_count}"
    end

    DT[:successful_processing] << { body: body, final_receive_count: receive_count }
  end
end

backoff_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, backoff_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

# Send a message
Shoryuken::Client.sqs.send_message(
  queue_url: queue_url,
  message_body: 'backoff test'
)

sleep 1

# Process - should fail twice then succeed on 3rd attempt
# Total time: ~1s (first retry) + ~2s (second retry) = ~3s minimum
poll_queues_until(timeout: 20) { DT[:successful_processing].size >= 1 }

# Verify the message was eventually processed successfully
assert_equal(1, DT[:successful_processing].size)
assert_equal('backoff test', DT[:successful_processing].first[:body])
assert_equal(3, DT[:successful_processing].first[:final_receive_count])

# Verify we had 3 attempts total
assert_equal(3, DT[:attempts].size, 'Should have 3 attempts total')

# Verify backoff timing - second attempt should be ~1s after first
first_to_second = DT[:attempts][1][:time] - DT[:attempts][0][:time]
assert(first_to_second >= 0.5, "Second attempt should be at least 0.5s after first (was #{first_to_second}s)")

# Verify backoff timing - third attempt should be ~2s after second
second_to_third = DT[:attempts][2][:time] - DT[:attempts][1][:time]
assert(second_to_third >= 1.0, "Third attempt should be at least 1s after second (was #{second_to_third}s)")
