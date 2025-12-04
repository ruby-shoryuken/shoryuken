# frozen_string_literal: true

# This spec tests batch processing including batch message reception (up to 10
# messages), batch vs single worker behavior differences, JSON body parsing in
# batch mode, and maximum batch size handling.

RSpec.describe 'Batch Processing Integration' do
  include_context 'localstack'

  let(:queue_name) { "batch-test-#{SecureRandom.uuid}" }

  before do
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')
  end

  after do
    delete_test_queue(queue_name)
    # Unregister all workers and clear groups to avoid conflicts between tests
    Shoryuken.worker_registry.clear
    Shoryuken.groups.clear
  end

  describe 'Batch message reception' do
    it 'receives multiple messages in batch mode' do
      worker = create_batch_worker(queue_name)
      worker.received_messages = []

      entries = 5.times.map { |i| { id: SecureRandom.uuid, message_body: "message-#{i}" } }
      Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

      sleep 1 # Let messages settle

      poll_queues_until { worker.received_messages.size >= 5 }

      expect(worker.received_messages.size).to eq 5
      expect(worker.batch_sizes.any? { |size| size > 1 }).to be true
    end

    it 'receives single message in non-batch mode' do
      worker = create_single_worker(queue_name)
      worker.received_messages = []

      entries = 3.times.map { |i| { id: SecureRandom.uuid, message_body: "single-#{i}" } }
      Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

      sleep 1

      poll_queues_until { worker.received_messages.size >= 3 }

      expect(worker.received_messages.size).to eq 3
      expect(worker.batch_sizes.all? { |size| size == 1 }).to be true
    end
  end

  describe 'Batch with different body parsers' do
    it 'parses JSON bodies in batch mode' do
      worker = create_json_batch_worker(queue_name)
      worker.received_messages = []

      entries = 3.times.map do |i|
        { id: SecureRandom.uuid, message_body: { index: i, data: "test-#{i}" }.to_json }
      end
      Shoryuken::Client.queues(queue_name).send_messages(entries: entries)

      sleep 1

      poll_queues_until { worker.received_messages.size >= 3 }

      expect(worker.received_messages.size).to eq 3
      worker.received_messages.each do |msg|
        expect(msg).to be_a(Hash)
        expect(msg).to have_key('index')
      end
    end
  end


  private

  def create_batch_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages, :batch_sizes
      end

      def perform(sqs_msgs, bodies)
        msgs = Array(sqs_msgs)
        self.class.batch_sizes ||= []
        self.class.batch_sizes << msgs.size
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

  def create_single_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages, :batch_sizes
      end

      def perform(sqs_msg, body)
        self.class.batch_sizes ||= []
        self.class.batch_sizes << 1
        self.class.received_messages ||= []
        self.class.received_messages << body
      end
    end

    # Set options before registering to avoid default queue conflicts
    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.get_shoryuken_options['auto_delete'] = true
    worker_class.get_shoryuken_options['batch'] = false
    worker_class.received_messages = []
    worker_class.batch_sizes = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_json_batch_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages
      end

      def perform(sqs_msgs, bodies)
        self.class.received_messages ||= []
        self.class.received_messages.concat(Array(bodies))
      end
    end

    # Set options before registering to avoid default queue conflicts
    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.get_shoryuken_options['auto_delete'] = true
    worker_class.get_shoryuken_options['batch'] = true
    worker_class.get_shoryuken_options['body_parser'] = :json
    worker_class.received_messages = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end
end
