# frozen_string_literal: true

# This spec tests that an error raised by the stop callback does not skip the
# rest of the shutdown sequence.
#
# Launcher#stop and #stop! run the on_stop callback first. An error from it used
# to propagate out of the stop sequence, so the managers were never stopped,
# the executor was never shut down and the :shutdown/:stopped events never
# fired - the process could not shut down cleanly.
#
# Expected behavior: the error is logged, and the remaining steps still run for
# both the graceful and the hard stop.
#
# Regression: a raising on_stop callback skipped the whole shutdown.

require 'timeout'

setup_sqs

DT.clear

Shoryuken.on_stop { raise 'on_stop failure' }
Shoryuken.on(:shutdown) { DT[:shutdown] << true }
Shoryuken.on(:stopped) { DT[:stopped] << true }

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, _body); end
end

worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker)

%i[stop stop!].each do |stop_method|
  DT.clear

  executor = Concurrent::CachedThreadPool.new(auto_terminate: true)
  Shoryuken.define_singleton_method(:launcher_executor) { executor }

  launcher = Shoryuken::Launcher.new
  launcher.start
  sleep 0.5

  begin
    Timeout.timeout(20) { launcher.public_send(stop_method) }
  rescue RuntimeError => e
    raise IntegrationsHelper::TestFailure, "Launcher##{stop_method} raised the on_stop error: #{e.message}"
  end

  assert(executor.shutdown?, "Launcher##{stop_method} must shut the executor down when on_stop raises")
  assert_equal(1, DT[:shutdown].size, "Launcher##{stop_method} must still fire :shutdown when on_stop raises")
  assert_equal(1, DT[:stopped].size, "Launcher##{stop_method} must still fire :stopped when on_stop raises")
end
