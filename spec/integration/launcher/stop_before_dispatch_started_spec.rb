# frozen_string_literal: true

# This spec tests that a graceful stop returns when a manager's dispatch loop never started.
#
# Manager#await_dispatching_in_progress waits on a signal that the dispatch loop closes when it sees the stop flag. A stop
# that arrives before Manager#start reaches the loop (the start Future not yet scheduled, or an embedded host whose
# executor is saturated) has no loop to close it. Here a :utilization_update handler, which Manager#start fires before it
# enters the loop, holds the start back until the stop has returned.
#
# Regression: Launcher#stop deadlocked when the stop arrived before the dispatch loop started (7.0.4).

require 'timeout'

setup_sqs

DT.clear

Shoryuken.options[:timeout] = 2

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker)

start_latch = Queue.new

Shoryuken.on(:utilization_update) do
  DT[:start_held] << true
  # Pop on the closed latch returns at once, so only the start waits
  start_latch.pop
end

Shoryuken.on(:stopped) { DT[:stopped] << true }

launcher = Shoryuken::Launcher.new
launcher.start

begin
  Timeout.timeout(10) { sleep 0.1 until DT[:start_held].size >= 1 }

  started_at = Time.now
  begin
    Timeout.timeout(Shoryuken.options[:timeout] + 10) { launcher.stop }
  rescue Timeout::Error
    raise(
      IntegrationsHelper::TestFailure,
      'Launcher#stop deadlocked awaiting a manager whose dispatch loop never started'
    )
  end
  elapsed = Time.now - started_at

  assert(
    elapsed < Shoryuken.options[:timeout] + 5,
    "Graceful stop should return within the #{Shoryuken.options[:timeout]}s timeout, took #{elapsed.round(1)}s"
  )
  assert_equal(1, DT[:stopped].size, ':stopped should fire once')
ensure
  start_latch.close
end
