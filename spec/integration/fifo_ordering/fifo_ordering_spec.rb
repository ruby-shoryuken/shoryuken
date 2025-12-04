# frozen_string_literal: true

# This spec tests FIFO queue ordering guarantees including message ordering
# within the same message group, processing across multiple message groups,
# deduplication within the 5-minute window, and batch processing on FIFO queues.

RSpec.describe 'FIFO Queue Ordering Integration' do
  include_context 'localstack'

  let(:queue_name) { "fifo-test-#{SecureRandom.uuid[0..7]}.fifo" }

  before do
    create_fifo_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')
  end

  after do
    delete_test_queue(queue_name)
    Shoryuken.worker_registry.clear
    Shoryuken.groups.clear
  end

  describe 'Message ordering within same group' do
    it 'maintains order for messages in same group' do
      worker = create_fifo_worker(queue_name)
      worker.received_messages = []
      worker.processing_order = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send ordered messages with same group
      5.times do |i|
        Shoryuken::Client.sqs.send_message(
          queue_url: queue_url,
          message_body: "msg-#{i}",
          message_group_id: 'group-a',
          message_deduplication_id: SecureRandom.uuid
        )
      end

      sleep 1

      poll_queues_until { worker.received_messages.size >= 5 }

      expect(worker.received_messages.size).to eq 5

      # Verify ordering
      expected = (0..4).map { |i| "msg-#{i}" }
      expect(worker.received_messages).to eq expected
    end
  end

  describe 'Multiple message groups' do
    it 'processes messages from different groups' do
      worker = create_fifo_worker(queue_name)
      worker.received_messages = []
      worker.groups_seen = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send messages to different groups
      %w[group-a group-b group-c].each do |group|
        2.times do |i|
          Shoryuken::Client.sqs.send_message(
            queue_url: queue_url,
            message_body: "#{group}-msg-#{i}",
            message_group_id: group,
            message_deduplication_id: SecureRandom.uuid
          )
        end
      end

      sleep 1

      poll_queues_until(timeout: 20) { worker.received_messages.size >= 6 }

      expect(worker.received_messages.size).to eq 6
      expect(worker.groups_seen.uniq.size).to eq 3
    end

    it 'maintains order within each group' do
      worker = create_fifo_worker(queue_name)
      worker.received_messages = []
      worker.messages_by_group = {}

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send ordered messages to multiple groups
      %w[group-x group-y].each do |group|
        3.times do |i|
          Shoryuken::Client.sqs.send_message(
            queue_url: queue_url,
            message_body: "#{group}-#{i}",
            message_group_id: group,
            message_deduplication_id: SecureRandom.uuid
          )
        end
      end

      sleep 1

      poll_queues_until(timeout: 20) { worker.received_messages.size >= 6 }

      # Check order within each group
      group_x_messages = worker.messages_by_group['group-x'] || []
      group_y_messages = worker.messages_by_group['group-y'] || []

      expect(group_x_messages).to eq %w[group-x-0 group-x-1 group-x-2]
      expect(group_y_messages).to eq %w[group-y-0 group-y-1 group-y-2]
    end
  end

  describe 'Message deduplication' do
    it 'deduplicates messages with same deduplication ID' do
      worker = create_fifo_worker(queue_name)
      worker.received_messages = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
      dedup_id = SecureRandom.uuid

      # Send same message multiple times with same deduplication ID
      3.times do
        Shoryuken::Client.sqs.send_message(
          queue_url: queue_url,
          message_body: 'duplicate-msg',
          message_group_id: 'dedup-group',
          message_deduplication_id: dedup_id
        )
      end

      sleep 2

      poll_queues_until(timeout: 10) { worker.received_messages.size >= 1 }

      # Wait a bit more to ensure no more messages come through
      sleep 2

      # Should only receive one message due to deduplication
      expect(worker.received_messages.size).to eq 1
    end
  end

  describe 'FIFO with batch workers' do
    it 'allows batch processing on FIFO queues' do
      worker = create_fifo_batch_worker(queue_name)
      worker.received_messages = []
      worker.batch_sizes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send messages
      5.times do |i|
        Shoryuken::Client.sqs.send_message(
          queue_url: queue_url,
          message_body: "batch-fifo-#{i}",
          message_group_id: 'batch-group',
          message_deduplication_id: SecureRandom.uuid
        )
      end

      sleep 1

      poll_queues_until { worker.received_messages.size >= 5 }

      expect(worker.received_messages.size).to eq 5
    end
  end

  private

  def create_fifo_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages, :processing_order, :groups_seen, :messages_by_group
      end

      def perform(sqs_msg, body)
        self.class.received_messages ||= []
        self.class.received_messages << body

        self.class.processing_order ||= []
        self.class.processing_order << Time.now

        # Extract group from message attributes if available
        group = sqs_msg.message_attributes&.dig('message_group_id', 'string_value')
        group ||= body.split('-')[0..1].join('-') if body.include?('-')

        self.class.groups_seen ||= []
        self.class.groups_seen << group if group

        self.class.messages_by_group ||= {}
        if group
          self.class.messages_by_group[group] ||= []
          self.class.messages_by_group[group] << body
        end
      end
    end

    # Set options before registering to avoid default queue conflicts
    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.get_shoryuken_options['auto_delete'] = true
    worker_class.get_shoryuken_options['batch'] = false
    worker_class.received_messages = []
    worker_class.processing_order = []
    worker_class.groups_seen = []
    worker_class.messages_by_group = {}
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_fifo_batch_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages, :batch_sizes
      end

      def perform(sqs_msgs, bodies)
        self.class.batch_sizes ||= []
        self.class.batch_sizes << Array(bodies).size

        self.class.received_messages ||= []
        self.class.received_messages.concat(Array(bodies))
      end
    end

    # Set options before registering to avoid default queue conflicts
    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.get_shoryuken_options['auto_delete'] = true
    worker_class.get_shoryuken_options['batch'] = true
    worker_class.received_messages = []
    worker_class.batch_sizes = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end
end
