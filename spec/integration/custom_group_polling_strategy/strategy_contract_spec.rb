# frozen_string_literal: true

# This spec tests how Shoryuken calls a custom polling strategy for a group
# with one FIFO queue and one standard queue.
#
# - The strategy is created once with the queue list expanded by weight
#   (weight 3 lists the queue 3 times) and the group delay
# - While next_queue returns nil, the manager waits and does not fetch
# - messages_found runs after every fetch with the fetched count, 0 included
# - message_processed runs once per processed message on the FIFO queue and
#   never on the standard queue

NIL_RETURNS = 3

class ContractRecordingStrategy < Shoryuken::Polling::BaseStrategy
  def initialize(queues, delay)
    super()
    DT[:initialized] << { queues: queues.dup, delay: delay }
    @queues = queues.uniq
    @index = 0
    @nil_returns = 0
  end

  def next_queue
    if @nil_returns < NIL_RETURNS
      @nil_returns += 1
      DT[:events] << [:next_queue_nil, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
      return nil
    end

    queue = @queues[@index % @queues.size]
    @index += 1
    Shoryuken::Polling::QueueConfiguration.new(queue, {})
  end

  def messages_found(queue, count)
    DT[:events] << [:messages_found, queue, count]
  end

  def message_processed(queue)
    DT[:events] << [:message_processed, queue]
  end

  def active_queues
    @queues.map { |queue| [queue, 1] }
  end
end

module FetchRecorder
  def fetch(queue, limit)
    messages = super
    DT[:events] << [:fetch, queue.name, messages.size]
    messages
  end
end

Shoryuken::Fetcher.prepend(FetchRecorder)

setup_sqs

FIFO_QUEUE = "#{DT.uuid}.fifo".freeze
STANDARD_QUEUE = DT.queues[0]

create_fifo_queue(FIFO_QUEUE)
create_test_queue(STANDARD_QUEUE)

Shoryuken.add_group('contract', 4, delay: 2, polling_strategy: ContractRecordingStrategy)
Shoryuken.add_queue(FIFO_QUEUE, 3, 'contract')
Shoryuken.add_queue(STANDARD_QUEUE, 1, 'contract')

class ContractFifoWorker
  include Shoryuken::Worker

  shoryuken_options queue: FIFO_QUEUE, auto_delete: true, batch: false

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

class ContractStandardWorker
  include Shoryuken::Worker

  shoryuken_options queue: STANDARD_QUEUE, auto_delete: true, batch: false

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

2.times do |i|
  Shoryuken::Client.queues(FIFO_QUEUE).send_message(message_body: "fifo-#{i}", message_group_id: "group-#{i}")
  Shoryuken::Client.queues(STANDARD_QUEUE).send_message(message_body: "standard-#{i}")
end

def events(type)
  DT[:events].select { |event| event.first == type }.map { |event| event.drop(1) }
end

poll_queues_until(timeout: 20) do
  DT[:processed].size >= 4 &&
    events(:message_processed).size >= 2 &&
    events(:messages_found).include?([FIFO_QUEUE, 0]) &&
    events(:messages_found).include?([STANDARD_QUEUE, 0])
end

assert_equal(
  [{ queues: [FIFO_QUEUE, FIFO_QUEUE, FIFO_QUEUE, STANDARD_QUEUE], delay: 2.0 }],
  DT[:initialized]
)

assert_equal(%w[fifo-0 fifo-1 standard-0 standard-1], DT[:processed].sort)

leading = DT[:events].first(NIL_RETURNS)
assert(leading.all? { |event| event.first == :next_queue_nil }, "Fetched before next_queue returned a queue: #{leading}")

leading.map(&:last).each_cons(2) do |a, b|
  assert(b - a >= 0.09, "Manager asked next_queue again after #{(b - a).round(3)}s instead of waiting")
end

assert_equal(events(:fetch), events(:messages_found))

assert_equal([[FIFO_QUEUE], [FIFO_QUEUE]], events(:message_processed))
