# frozen_string_literal: true

# This spec tests that a manager whose stop_new_dispatching raises does not hang
# the graceful stop.
#
# Launcher#stop signals every manager and then awaits each one. A manager whose
# stop_new_dispatching raises before it sets its stop flag never closes its
# release signal, so awaiting it blocks on Queue#pop forever, and a rescue
# around the wait cannot unblock it.
#
# The error is logged, the failed manager is not awaited,
# the other manager is still stopped and awaited, the executor is shut down and
# :stopped fires.
#
# Regression: the graceful stop hung while awaiting the failed manager.

require 'timeout'

setup_sqs

DT.clear

failing_group = 'failing'

Shoryuken::Manager.prepend(
  Module.new do
    define_method(:stop_new_dispatching) do
      raise 'stop_new_dispatching failure' if group == failing_group

      super()
    end
  end
)

Shoryuken.on(:stopped) { DT[:stopped] << true }

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, _body); end
end

[failing_group, 'healthy'].each do |group|
  queue_name = "#{DT.queue}-#{group}"
  create_test_queue(queue_name)
  Shoryuken.add_group(group, 1)
  Shoryuken.add_queue(queue_name, 1, group)
  Shoryuken.register_worker(queue_name, worker)
end

executor = Concurrent::CachedThreadPool.new(auto_terminate: true)
Shoryuken.define_singleton_method(:launcher_executor) { executor }

launcher = Shoryuken::Launcher.new
launcher.start
sleep 1

begin
  Timeout.timeout(20) { launcher.stop }
rescue Timeout::Error
  raise IntegrationsHelper::TestFailure, 'Launcher#stop hung awaiting the manager whose stop_new_dispatching raised'
end

assert(executor.shutdown?, 'Launcher#stop must shut the executor down when a manager fails to stop')
assert_equal(1, DT[:stopped].size, 'Launcher#stop must still fire :stopped when a manager fails to stop')
