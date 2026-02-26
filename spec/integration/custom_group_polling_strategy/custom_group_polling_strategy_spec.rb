# frozen_string_literal: true

# This spec tests that a custom polling strategy can be configured per-group
# via the add_group API.
#
# Bug #925: Cannot configure custom polling_strategy from YAML config
# The add_group method does not accept a polling_strategy parameter,
# making it impossible to set a per-group polling strategy programmatically.
# Additionally, polling_strategy() reads from options[:groups] (raw config)
# rather than from groups (the processed hash populated by add_group).

# Define a custom polling strategy
class CustomRoundRobin < Shoryuken::Polling::BaseStrategy
  def initialize(queues, delay = nil)
    @queues = queues.dup.uniq
    @delay = delay
    @index = 0
  end

  def next_queue
    return nil if @queues.empty?

    queue = @queues[@index % @queues.length]
    @index += 1
    Shoryuken::Polling::QueueConfiguration.new(queue, {})
  end

  def messages_found(_queue, _count)
    # noop
  end

  def active_queues
    @queues.map { |q| [q, 1] }
  end
end

# ---- Part 1: API assertion (no SQS needed) ----
# Bug: add_group does not accept polling_strategy: keyword argument
# This should work but currently raises ArgumentError
Shoryuken.add_group('custom_group', 1, polling_strategy: CustomRoundRobin)

# Bug: polling_strategy() should return our custom strategy for the group
strategy = Shoryuken.polling_strategy('custom_group')
assert_equal(
  CustomRoundRobin,
  strategy,
  "Expected polling_strategy('custom_group') to return CustomRoundRobin, got #{strategy.inspect}"
)

# ---- Part 2: End-to-end with SQS ----
setup_localstack

queue_name = DT.queues[0]
create_test_queue(queue_name)

Shoryuken.groups.clear
Shoryuken.add_group('custom_group', 1, polling_strategy: CustomRoundRobin)
Shoryuken.add_queue(queue_name, 1, 'custom_group')

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker_class)

Shoryuken::Client.queues(queue_name).send_message(message_body: 'custom-strategy-msg')

sleep 1

poll_queues_until { DT[:processed].size >= 1 }

assert_equal(1, DT[:processed].size)
assert_equal('custom-strategy-msg', DT[:processed].first)
