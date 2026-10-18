# frozen_string_literal: true

# This spec tests auto_visibility_timeout together with retry_intervals
# (ExponentialBackoffRetry) on a worker that runs past one extension and then
# raises.
#
# The queue's VisibilityTimeout is 6s, so the message is extended every 1s
# while the worker runs for 3s. Then the worker raises and the backoff sets the
# visibility timeout to 12s.
#
# Expected behavior: the extension timer stops when perform ends, so the
# backoff is the last visibility change. The message comes back after the 12s
# backoff, not after the queue's 6s VisibilityTimeout.

setup_sqs

DT.clear

module VisibilitySpy
  def change_visibility(options)
    DT[:visibility_changes] << [Time.now, options[:visibility_timeout]]
    super
  end
end

Shoryuken::Message.prepend(VisibilitySpy)

queue_name = DT.uuid
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '6' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

backoff_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_visibility_timeout: true, auto_delete: true, retry_intervals: [12]

  def perform(sqs_msg, _body)
    DT[:starts] << Time.now
    return if sqs_msg.attributes['ApproximateReceiveCount'].to_i > 1

    sleep 3
    DT[:failed_at] << Time.now
    raise 'boom'
  end
end

backoff_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, backoff_worker)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'fails once')

# A short extra wait lets a late visibility change still show up
poll_queues_until(timeout: 30) { DT[:starts].size >= 2 && sleep(2) }

assert_equal(2, DT[:starts].size, "the message must be performed twice, got #{DT[:starts].size}")

failed_at = DT[:failed_at].first
during_perform = DT[:visibility_changes].select { |at, _| at < failed_at }.map(&:last)
after_perform = DT[:visibility_changes].select { |at, _| at >= failed_at }.map(&:last)

assert(during_perform.size >= 2, "the message must be extended while perform runs, got #{during_perform}")
assert(during_perform.all?(6), "extensions must use the queue VisibilityTimeout, got #{during_perform}")
assert_equal([12], after_perform, 'the backoff must be the only visibility change after the failure')

comeback = DT[:starts].last - failed_at
assert(comeback >= 11, "the message must stay invisible for the 12s backoff, it came back after #{comeback.round(1)}s")
assert(comeback < 18, "the message must come back after the 12s backoff, it came back after #{comeback.round(1)}s")

delete_test_queue(queue_name)
