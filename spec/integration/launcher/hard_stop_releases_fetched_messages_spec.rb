# frozen_string_literal: true

# This spec tests that a message fetched while the launcher is hard-stopping is
# released (visibility timeout 0) instead of being left in flight.
#
# Launcher#stop! shuts the executor down while a long poll may still be in
# flight. When that poll returns a message, Manager#assign sees the manager is
# no longer running and skips it. It used to just drop the message, so it stayed
# invisible on SQS for the whole queue visibility timeout before any other
# consumer could receive it.
#
# Expected behavior: the skipped message is made visible again at once, and it
# is never processed by the stopping launcher.
#
# Regression: the message stayed in flight for the full visibility timeout.

require 'timeout'

setup_sqs

DT.clear

queue_name = DT.queue
# Far longer than the spec runs, so the message can only reappear if released.
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '60' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.sqs_client_receive_message_opts['default'] = { wait_time_seconds: 5 }

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

launcher = Shoryuken::Launcher.new
launcher.start

# Let the dispatch loop enter its long poll on the empty queue.
sleep 1

stopper = Thread.new { launcher.stop! }

# Send only once the executor is shutting down, so the in-flight poll returns the
# message to a manager that is no longer running.
Timeout.timeout(5) { sleep 0.05 while launcher.send(:executor).running? }
Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'fetched during stop')

Timeout.timeout(20) { stopper.join }

received = Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 3).messages

assert_equal(
  1,
  received.size,
  'a message fetched during a hard stop must be released at once, not stay in flight for the visibility timeout'
)
assert_equal('fetched during stop', received.first.body)
assert(DT[:processed].empty?, 'the stopping launcher must not process the fetched message')
