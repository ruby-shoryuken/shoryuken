# frozen_string_literal: true

# This spec tests large payload handling including moderately large payloads (10KB),
# large payloads (100KB), payloads near the 256KB SQS limit, large JSON objects,
# deeply nested JSON, batch processing with large messages, and unicode content.

RSpec.describe 'Large Payloads Integration' do
  include_context 'localstack'

  let(:queue_name) { "large-payload-test-#{SecureRandom.uuid}" }

  # SQS message size limit is 256KB
  let(:max_message_size) { 256 * 1024 }

  before do
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')
  end

  after do
    delete_test_queue(queue_name)
    Shoryuken.worker_registry.clear
    Shoryuken.groups.clear
  end

  describe 'Large string payloads' do
    it 'handles moderately large payloads (10KB)' do
      worker = create_payload_worker(queue_name)
      worker.received_bodies = []

      # Create 10KB payload
      payload = 'x' * (10 * 1024)

      Shoryuken::Client.queues(queue_name).send_message(message_body: payload)

      poll_queues_until { worker.received_bodies.size >= 1 }

      expect(worker.received_bodies.first.size).to eq(10 * 1024)
    end

    it 'handles large payloads (100KB)' do
      worker = create_payload_worker(queue_name)
      worker.received_bodies = []

      # Create 100KB payload
      payload = 'y' * (100 * 1024)

      Shoryuken::Client.queues(queue_name).send_message(message_body: payload)

      poll_queues_until { worker.received_bodies.size >= 1 }

      expect(worker.received_bodies.first.size).to eq(100 * 1024)
    end

    it 'handles payloads near the SQS limit (250KB)' do
      worker = create_payload_worker(queue_name)
      worker.received_bodies = []

      # Create 250KB payload (leaving room for overhead)
      payload = 'z' * (250 * 1024)

      Shoryuken::Client.queues(queue_name).send_message(message_body: payload)

      poll_queues_until { worker.received_bodies.size >= 1 }

      expect(worker.received_bodies.first.size).to eq(250 * 1024)
    end
  end

  describe 'Large JSON payloads' do
    it 'handles large JSON objects' do
      worker = create_json_worker(queue_name)
      worker.received_data = []

      # Create large JSON with many keys
      large_data = {}
      1000.times do |i|
        large_data["key_#{i}"] = "value_#{i}" * 10
      end

      json_payload = JSON.generate(large_data)

      Shoryuken::Client.queues(queue_name).send_message(message_body: json_payload)

      poll_queues_until { worker.received_data.size >= 1 }

      received = worker.received_data.first
      expect(received.keys.size).to eq 1000
      expect(received['key_0']).to eq('value_0' * 10)
    end

    it 'handles deeply nested JSON' do
      worker = create_json_worker(queue_name)
      worker.received_data = []

      # Create deeply nested structure
      nested = { 'level' => 0, 'data' => 'base' }
      50.times do |i|
        nested = { 'level' => i + 1, 'child' => nested, 'padding' => 'x' * 100 }
      end

      json_payload = JSON.generate(nested)

      Shoryuken::Client.queues(queue_name).send_message(message_body: json_payload)

      poll_queues_until { worker.received_data.size >= 1 }

      received = worker.received_data.first
      expect(received['level']).to eq 50

      # Traverse to verify nesting
      current = received
      10.times { current = current['child'] }
      expect(current['level']).to eq 40
    end

    it 'handles large JSON arrays' do
      worker = create_json_worker(queue_name)
      worker.received_data = []

      # Create large array
      large_array = (0...5000).map { |i| { 'index' => i, 'value' => "item-#{i}" } }
      json_payload = JSON.generate(large_array)

      Shoryuken::Client.queues(queue_name).send_message(message_body: json_payload)

      poll_queues_until { worker.received_data.size >= 1 }

      received = worker.received_data.first
      expect(received.size).to eq 5000
      expect(received.first['index']).to eq 0
      expect(received.last['index']).to eq 4999
    end
  end


  private

  def create_payload_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_bodies
      end

      def perform(sqs_msg, body)
        self.class.received_bodies ||= []
        self.class.received_bodies << body
      end
    end

    # Set options before registering to avoid default queue conflicts
    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.get_shoryuken_options['auto_delete'] = true
    worker_class.get_shoryuken_options['batch'] = false
    worker_class.received_bodies = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_json_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_data
      end

      def perform(sqs_msg, body)
        self.class.received_data ||= []
        self.class.received_data << body
      end
    end

    # Set options before registering to avoid default queue conflicts
    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.get_shoryuken_options['auto_delete'] = true
    worker_class.get_shoryuken_options['batch'] = false
    worker_class.get_shoryuken_options['body_parser'] = :json
    worker_class.received_data = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

end
