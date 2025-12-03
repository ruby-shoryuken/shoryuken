# frozen_string_literal: true

# This spec tests polling strategies including WeightedRoundRobin (default),
# StrictPriority, queue pause/unpause behavior on empty queues, and
# multi-queue worker message distribution.

RSpec.describe 'Polling Strategies Integration' do
  include_context 'localstack'

  let(:queue_prefix) { "polling-#{SecureRandom.uuid[0..7]}" }
  let(:queue_high) { "#{queue_prefix}-high" }
  let(:queue_medium) { "#{queue_prefix}-medium" }
  let(:queue_low) { "#{queue_prefix}-low" }

  after do
    [queue_high, queue_medium, queue_low].each do |queue|
      delete_test_queue(queue)
    end
  end

  describe 'Weighted Round Robin Strategy' do
    before do
      [queue_high, queue_medium, queue_low].each do |queue|
        create_test_queue(queue)
      end

      Shoryuken.add_group('default', 1)
      # Higher weight = higher priority
      Shoryuken.add_queue(queue_high, 3, 'default')
      Shoryuken.add_queue(queue_medium, 2, 'default')
      Shoryuken.add_queue(queue_low, 1, 'default')
    end

    it 'processes messages from multiple queues' do
      worker = create_multi_queue_worker([queue_high, queue_medium, queue_low])
      worker.messages_by_queue = {}

      # Send messages to all queues
      Shoryuken::Client.queues(queue_high).send_message(message_body: 'high-msg')
      Shoryuken::Client.queues(queue_medium).send_message(message_body: 'medium-msg')
      Shoryuken::Client.queues(queue_low).send_message(message_body: 'low-msg')

      sleep 1

      poll_queues_until { worker.total_messages >= 3 }

      expect(worker.messages_by_queue.keys.size).to eq 3
      expect(worker.total_messages).to eq 3
    end

    it 'favors higher weight queues' do
      worker = create_multi_queue_worker([queue_high, queue_medium, queue_low])
      worker.messages_by_queue = {}
      worker.processing_order = []

      # Send multiple messages to each queue
      3.times { Shoryuken::Client.queues(queue_high).send_message(message_body: 'high') }
      3.times { Shoryuken::Client.queues(queue_medium).send_message(message_body: 'medium') }
      3.times { Shoryuken::Client.queues(queue_low).send_message(message_body: 'low') }

      sleep 1

      poll_queues_until(timeout: 20) { worker.total_messages >= 9 }

      expect(worker.total_messages).to eq 9

      # High priority queue should generally be processed more frequently early on
      first_five = worker.processing_order.first(5)
      high_count = first_five.count { |q| q.include?('high') }
      expect(high_count).to be >= 2
    end
  end

  describe 'Strict Priority Strategy' do
    before do
      [queue_high, queue_medium, queue_low].each do |queue|
        create_test_queue(queue)
      end

      Shoryuken.add_group('strict', 1)
      Shoryuken.groups['strict'][:polling_strategy] = Shoryuken::Polling::StrictPriority

      # Order matters for strict priority
      Shoryuken.add_queue(queue_high, 1, 'strict')
      Shoryuken.add_queue(queue_medium, 1, 'strict')
      Shoryuken.add_queue(queue_low, 1, 'strict')
    end

    it 'processes higher priority queues first' do
      worker = create_multi_queue_worker([queue_high, queue_medium, queue_low])
      worker.messages_by_queue = {}
      worker.processing_order = []

      # Send to all queues
      Shoryuken::Client.queues(queue_low).send_message(message_body: 'low')
      Shoryuken::Client.queues(queue_medium).send_message(message_body: 'medium')
      Shoryuken::Client.queues(queue_high).send_message(message_body: 'high')

      sleep 1

      poll_queues_until { worker.total_messages >= 3 }

      expect(worker.processing_order.first).to include('high')
    end
  end

  describe 'Queue pause/unpause behavior' do
    before do
      create_test_queue(queue_high)
      Shoryuken.add_group('default', 1)
      Shoryuken.add_queue(queue_high, 1, 'default')
    end

    it 'continues polling after empty queue' do
      worker = create_simple_worker(queue_high)
      worker.received_messages = []

      # Start with empty queue, then add message after delay
      Thread.new do
        sleep 2
        Shoryuken::Client.queues(queue_high).send_message(message_body: 'delayed-msg')
      end

      poll_queues_until(timeout: 10) { worker.received_messages.size >= 1 }

      expect(worker.received_messages.size).to eq 1
    end
  end

  private

  def create_multi_queue_worker(queues)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :messages_by_queue, :processing_order
      end

      shoryuken_options auto_delete: true, batch: false

      def perform(sqs_msg, body)
        queue = sqs_msg.queue_url.split('/').last
        self.class.messages_by_queue ||= {}
        self.class.messages_by_queue[queue] ||= []
        self.class.messages_by_queue[queue] << body
        self.class.processing_order ||= []
        self.class.processing_order << queue
      end

      def self.total_messages
        (messages_by_queue || {}).values.flatten.size
      end
    end

    queues.each do |queue|
      worker_class.get_shoryuken_options['queue'] = queue
      Shoryuken.register_worker(queue, worker_class)
    end

    worker_class.messages_by_queue = {}
    worker_class.processing_order = []
    worker_class
  end

  def create_simple_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages
      end

      shoryuken_options auto_delete: true, batch: false

      def perform(sqs_msg, body)
        self.class.received_messages ||= []
        self.class.received_messages << body
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.received_messages = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end
end
