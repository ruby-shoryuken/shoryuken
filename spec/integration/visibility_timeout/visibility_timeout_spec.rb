# frozen_string_literal: true

# This spec tests visibility timeout management including manual visibility
# extension during long processing, message redelivery after timeout expiration,
# and auto_delete behavior with visibility timeout.

RSpec.describe 'Visibility Timeout Integration' do
  include_context 'localstack'

  let(:queue_name) { "visibility-test-#{SecureRandom.uuid}" }

  before do
    # Create queue with short visibility timeout for testing
    create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '5' })
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')
  end

  after do
    delete_test_queue(queue_name)
  end

  describe 'Manual visibility timeout changes' do
    it 'extends visibility timeout during processing' do
      worker = create_slow_worker(queue_name, processing_time: 2)
      worker.received_messages = []
      worker.visibility_extended = false

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'extend-test')

      poll_queues_until { worker.received_messages.size >= 1 }

      expect(worker.received_messages.size).to eq 1
      expect(worker.visibility_extended).to be true
    end

    it 'message becomes visible again after timeout expires without extension' do
      worker = create_non_extending_worker(queue_name)
      worker.received_messages = []
      worker.message_ids = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'redelivery-test')

      # First receive
      poll_queues_until(timeout: 8) { worker.received_messages.size >= 1 }

      first_receive_count = worker.received_messages.size

      # Wait for visibility timeout to expire and message to be redelivered
      sleep 6

      # Poll again to get redelivered message
      poll_queues_until(timeout: 8) { worker.received_messages.size > first_receive_count }

      expect(worker.received_messages.size).to be > first_receive_count
    end
  end

  describe 'Visibility timeout with auto_delete' do
    it 'deletes message after successful processing' do
      worker = create_auto_delete_worker(queue_name)
      worker.received_messages = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'auto-delete-test')

      poll_queues_until { worker.received_messages.size >= 1 }

      expect(worker.received_messages.size).to eq 1

      # Wait and verify message is not redelivered
      sleep 6

      poll_queues_briefly

      expect(worker.received_messages.size).to eq 1
    end
  end

  private

  def create_slow_worker(queue, processing_time:)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages, :visibility_extended
      end

      shoryuken_options auto_delete: true, batch: false

      def perform(sqs_msg, body)
        # Extend visibility before long processing
        sqs_msg.change_visibility(visibility_timeout: 30)
        self.class.visibility_extended = true

        sleep 2 # Simulate slow processing

        self.class.received_messages ||= []
        self.class.received_messages << body
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.received_messages = []
    worker_class.visibility_extended = false
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_non_extending_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages, :message_ids
      end

      shoryuken_options auto_delete: false, batch: false

      def perform(sqs_msg, body)
        self.class.received_messages ||= []
        self.class.received_messages << body
        self.class.message_ids ||= []
        self.class.message_ids << sqs_msg.message_id
        # Don't delete - let visibility timeout expire
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.received_messages = []
    worker_class.message_ids = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_auto_delete_worker(queue)
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
