# frozen_string_literal: true

# This spec tests that a manager's graceful stop can be awaited more than once instead of deadlocking.
#
# Operationally this is a graceful stop requested while another is still waiting on the manager, e.g. an embedded host
# that calls Launcher#stop from two threads. Launcher#stop does nothing once a stop has completed, so the spec drives
# the manager itself.
#
# Regression: Manager#await_dispatching_in_progress popped a Queue that
# received exactly one signal when the dispatch loop observed the stop flag.
# A second Launcher#stop popped an empty queue and blocked forever, leaving
# the process stuck in the signal loop where even TERM/INT were no longer
# processed - only SIGKILL could stop it (TSTP followed by USR1).

require 'timeout'

setup_sqs

DT.clear

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

stop_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

stop_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, stop_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

executor = Concurrent::CachedThreadPool.new(auto_terminate: true)
manager = Shoryuken::Manager.new(
  'default',
  Shoryuken::Fetcher.new('default'),
  Shoryuken.polling_strategy('default').new(Shoryuken.groups['default'][:queues], Shoryuken.delay('default')),
  1,
  executor
)
Concurrent::Future.execute { manager.start }

begin
  # Prove the manager is fully up and dispatching before stopping it
  Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'before stop')
  Timeout.timeout(10) { sleep 0.5 until DT[:processed].size >= 1 }

  manager.stop_new_dispatching
  Timeout.timeout(10) { manager.await_dispatching_in_progress }

  manager.stop_new_dispatching
  begin
    Timeout.timeout(10) { manager.await_dispatching_in_progress }
  rescue Timeout::Error
    raise(
      IntegrationsHelper::TestFailure,
      'Second await_dispatching_in_progress deadlocked on an empty signal queue ' \
      '(a second graceful stop leaves the process unkillable except SIGKILL)'
    )
  end

  assert_equal(['before stop'], DT[:processed].to_a, 'Message sent before shutdown should have been processed')
ensure
  executor.shutdown
  executor.kill unless executor.wait_for_termination(10)
end
