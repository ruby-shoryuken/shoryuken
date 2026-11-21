# frozen_string_literal: true

# This spec tests that retry_intervals reuses its last interval once the attempts
# outnumber the configured intervals. With [1, 3] the retries come after ~1s, ~3s
# and ~3s again, well below the queue's 30s visibility timeout.

setup_sqs

queue_name = DT.queue

create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '30' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

backoff_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options retry_intervals: [1, 3], auto_delete: true

  def perform(sqs_msg, body)
    receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
    DT[:attempts] << Time.now

    raise "Simulated failure on attempt #{receive_count}" if receive_count < 4

    DT[:successful_processing] << { body: body, final_receive_count: receive_count }
  end
end

backoff_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, backoff_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

Shoryuken::Client.sqs.send_message(
  queue_url: queue_url,
  message_body: 'beyond intervals test'
)

poll_queues_until(timeout: 25) { DT[:successful_processing].size >= 1 }

assert_equal(1, DT[:successful_processing].size)
assert_equal('beyond intervals test', DT[:successful_processing].first[:body])
assert_equal(4, DT[:successful_processing].first[:final_receive_count])
assert_equal(4, DT[:attempts].size)

gaps = DT[:attempts].each_cons(2).map { |earlier, later| later - earlier }

assert(gaps[0] >= 0.5 && gaps[0] < 2.5, "First retry should come after ~1s (was #{gaps[0]}s)")
assert(gaps[1] >= 2.0 && gaps[1] < 5.0, "Second retry should come after ~3s (was #{gaps[1]}s)")
assert(gaps[2] >= 2.0 && gaps[2] < 5.0, "Third retry should reuse the last interval of ~3s (was #{gaps[2]}s)")
assert((gaps[2] - gaps[1]).abs < 1, "Third retry gap should match the second (#{gaps[2]}s vs #{gaps[1]}s)")
