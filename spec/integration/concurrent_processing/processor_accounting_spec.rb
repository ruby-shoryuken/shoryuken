# frozen_string_literal: true

# This spec tests that the manager's busy-processor accounting stays correct
# when processor completion handling itself raises.
#
# Manager#processor_done makes SQS calls (Shoryuken::Client.queues, #fifo?)
# and invokes the polling strategy's message_processed callback (a documented
# extension point) - any of these can raise, e.g. on a transient network
# error or a bug in a custom strategy.
#
# Expected behavior: processor_done runs exactly once per processed message
# and busy_processors never goes negative, even when processor_done raises.
#
# Regression: Manager#assign chained `.then { processor_done }` with
# `.rescue { processor_done }`, so an exception inside processor_done
# rejected the then-promise and ran processor_done a SECOND time. The busy
# counter was decremented twice for one message and drifted negative,
# inflating `ready` and silently breaking the concurrency limit for the
# life of the process.

require 'timeout'

setup_sqs

DT.clear

queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(queue_name)

# A custom polling strategy whose message_processed callback raises, like a
# buggy user strategy or one that performs I/O and hits a transient error.
# Manager#processor_done invokes it for FIFO queues.
class FlakyCallbackStrategy < Shoryuken::Polling::WeightedRoundRobin
  def message_processed(queue)
    DT[:message_processed_calls] << { queue: queue, time: Time.now }
    raise 'flaky message_processed callback'
  end
end

Shoryuken.add_group('default', 2, polling_strategy: FlakyCallbackStrategy)
Shoryuken.add_queue(queue_name, 1, 'default')

accounting_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

accounting_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, accounting_worker)

# busy_processors is exposed through the public utilization_update event
Shoryuken.on(:utilization_update) do |opts|
  DT[:utilization] << opts.dup
end

launcher = Shoryuken::Launcher.new
launcher.start

begin
  Shoryuken::Client.queues(queue_name).send_message(message_body: 'hello')

  # Wait for the message to be processed and the completion path to run
  Timeout.timeout(15) { sleep 0.5 until DT[:message_processed_calls].size >= 1 }

  # Give the (buggy) rescue path time to run processor_done a second time
  sleep 3

  assert_equal(['hello'], DT[:processed].to_a, 'Message should have been processed exactly once')

  assert_equal(
    1,
    DT[:message_processed_calls].size,
    'processor_done must run exactly once per message, even when it raises ' \
    "(message_processed was called #{DT[:message_processed_calls].size} times)"
  )

  negative = DT[:utilization].select { |u| u[:busy_processors].negative? }
  assert(
    negative.empty?,
    'busy_processors must never go negative; a double decrement inflates ready ' \
    "and breaks the concurrency limit (saw: #{negative.first.inspect})"
  )
ensure
  begin
    Timeout.timeout(10) { launcher.stop }
  rescue Timeout::Error
    nil
  end
end
