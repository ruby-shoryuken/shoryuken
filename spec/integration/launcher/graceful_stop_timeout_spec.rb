# frozen_string_literal: true

# This spec tests that a graceful stop is bounded by the configured timeout and
# does not block forever on a worker that refuses to finish.
#
# Launcher#stop (the soft shutdown behind USR1/TSTP) waits for in-flight workers
# to finish so their messages are not redelivered. It used to call
# executor.wait_for_termination with no argument - an unbounded wait - so a
# single hung worker would block the shutdown forever (and, because the signal
# loop is stuck, leave the process killable only with SIGKILL).
#
# Expected behavior: workers get up to Shoryuken.options[:timeout] seconds to
# finish, after which the executor is killed and stop returns. Launcher#stop!
# already did this; Launcher#stop should too.
#
# Regression: a hung worker hung Launcher#stop indefinitely.

require 'timeout'

setup_sqs

DT.clear

# Short grace period so the test is fast; the worker hangs well past it.
Shoryuken.options[:timeout] = 2

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

hanging_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, _body)
    DT[:started] << true
    # Hang far longer than the grace period to simulate a stuck worker.
    sleep 60
  end
end

hanging_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, hanging_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

launcher = Shoryuken::Launcher.new
launcher.start

Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'hang')

# Make sure the worker is genuinely in-flight before we stop.
Timeout.timeout(15) { sleep 0.2 until DT[:started].size >= 1 }

# Graceful stop must return within roughly the grace period, not block for the
# full 60s the worker sleeps. Allow generous margin over the 2s timeout.
started_at = Time.now
begin
  Timeout.timeout(20) { launcher.stop }
rescue Timeout::Error
  raise IntegrationsHelper::TestFailure,
        'Launcher#stop blocked past the configured timeout on a hung worker: ' \
        'a graceful stop must bound executor.wait_for_termination and kill the ' \
        'executor when exceeded (an unbounded wait hangs USR1/TSTP shutdown forever)'
end
elapsed = Time.now - started_at

assert(
  elapsed < 15,
  "Graceful stop should return shortly after the #{Shoryuken.options[:timeout]}s timeout, " \
  "took #{elapsed.round(1)}s"
)
