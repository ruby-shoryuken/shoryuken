# frozen_string_literal: true

# This spec tests that a batch worker with retry_intervals and auto_visibility_timeout logs each "isn't supported for
# batch workers" warning once per worker class, not on every batch.
#
# Both options stay skipped for batches: the failed batch comes back after the queue's 1s visibility timeout, not after
# the 60s retry interval.

setup_sqs

log = StringIO.new
Shoryuken.logger = Logger.new(log)

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '1' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options(
    queue: queue_name, batch: true, auto_delete: true,
    retry_intervals: [60], auto_visibility_timeout: true
  )

  def perform(sqs_msgs, _bodies)
    DT[:batches] << sqs_msgs.size
    raise 'first batch fails' if DT[:batches].size == 1
  end
end
Shoryuken.register_worker(queue_name, worker)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'batch')

poll_queues_until(timeout: 20) { DT[:batches].size >= 2 }

['Exponential backoff', 'Auto extend visibility'].each do |option|
  warning = "#{option} isn't supported for batch workers"

  assert_equal(1, log.string.scan(warning).size)
  assert_includes(log.string, "#{warning}, skipping it for #{worker}")
end
