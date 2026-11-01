# frozen_string_literal: true

# This spec tests that Launcher#stop! kills a worker still busy past `timeout`
# and keeps its message, so SQS delivers it again.
#
# `stop!` returns within the configured `timeout` (plus a margin) without
# waiting for the busy worker to finish. The killed worker's message is not
# deleted (auto_delete runs only after `perform` returns), so it becomes
# visible again after the queue's visibility timeout.
#
# Regression: #215 - a hard shutdown hung while some workers were busy
# (CHANGELOG v2.0.7, "Fix hard shutdown if there are some busy workers").

require 'timeout'

setup_sqs

DT.clear

Shoryuken.options[:timeout] = 2

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '5' })
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

busy_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, _body)
    DT[:started] << Thread.current
    sleep 60
  end
end

busy_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, busy_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

launcher = Shoryuken::Launcher.new
launcher.start

Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'in flight')

Timeout.timeout(15) { sleep 0.2 until DT[:started].size >= 1 }

started_at = Time.now
Timeout.timeout(20) { launcher.stop! }
elapsed = Time.now - started_at

assert(elapsed < 7, "stop! must return within the timeout, took #{elapsed.round(1)}s")
assert(DT[:started].first.join(1), 'the busy worker thread must be killed, not left running')
assert_equal(1, queue_size(queue_name), 'the killed worker\'s message must not be deleted')

messages = Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 15).messages
assert_equal(['in flight'], messages.map(&:body), 'the in-flight message must come back after the visibility timeout')
