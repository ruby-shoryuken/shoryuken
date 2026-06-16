# frozen_string_literal: true

# This spec tests that stopping the launcher does not destroy the process-wide
# Concurrent.global_io_executor.
#
# When no launcher_executor is configured, Launcher#executor used to fall back
# to Concurrent.global_io_executor - and Launcher#stop / #stop! call
# executor.shutdown (and kill). That pool is a process-global singleton shared
# by anything using concurrent-ruby's :io pool (including Shoryuken's own
# ShoryukenConcurrentSendAdapter), so shutting it down breaks unrelated work and
# prevents a fresh launcher from being started in the same process.
#
# Expected behavior: the launcher owns a dedicated executor, so stopping it
# leaves the global IO executor untouched.
#
# Regression: stopping the launcher shut down/killed the global IO executor.

require 'timeout'

setup_sqs

# Exercise the real default executor path. The integrations helper injects a
# dedicated pool via launcher_executor; production CLI/embedded use leaves it
# nil, which is exactly the path that fell back to the global pool.
Shoryuken.define_singleton_method(:launcher_executor) { nil }

DT.clear

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

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

launcher = Shoryuken::Launcher.new
launcher.start

Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'hello')
Timeout.timeout(15) { sleep 0.2 until DT[:processed].size >= 1 }

launcher.stop!

# The process-global IO executor must still be running after the launcher stops.
assert(
  Concurrent.global_io_executor.running?,
  'Launcher must not shut down the process-global IO executor on stop; ' \
  'other code (including ShoryukenConcurrentSendAdapter) relies on it'
)

# ...and it must still actually run work scheduled on it.
result =
  begin
    Concurrent::Promises.future_on(Concurrent.global_io_executor) { 42 }.value(5)
  rescue Concurrent::RejectedExecutionError
    nil
  end

assert_equal(
  42, result,
  'A task scheduled on the global IO executor after the launcher stops should still run; ' \
  'the launcher destroyed the shared pool'
)
