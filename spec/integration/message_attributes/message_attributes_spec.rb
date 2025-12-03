# frozen_string_literal: true

# This spec tests SQS message attributes including String, Number, and Binary
# attribute types, system attributes (ApproximateReceiveCount, SentTimestamp),
# custom type suffixes, and attribute-based message filtering in workers.

RSpec.describe 'Message Attributes Integration' do
  include_context 'localstack'

  let(:queue_name) { "attributes-test-#{SecureRandom.uuid}" }

  before do
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')
  end

  after do
    delete_test_queue(queue_name)
  end

  describe 'String attributes' do
    it 'receives string message attributes' do
      worker = create_attribute_worker(queue_name)
      worker.received_attributes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'string-attr-test',
        message_attributes: {
          'CustomString' => {
            string_value: 'hello-world',
            data_type: 'String'
          },
          'AnotherString' => {
            string_value: 'foo-bar',
            data_type: 'String'
          }
        }
      )

      poll_queues_until { worker.received_attributes.size >= 1 }

      attrs = worker.received_attributes.first
      expect(attrs['CustomString']&.string_value).to eq 'hello-world'
      expect(attrs['AnotherString']&.string_value).to eq 'foo-bar'
    end
  end

  describe 'Number attributes' do
    it 'receives numeric message attributes' do
      worker = create_attribute_worker(queue_name)
      worker.received_attributes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'number-attr-test',
        message_attributes: {
          'IntValue' => {
            string_value: '42',
            data_type: 'Number'
          },
          'FloatValue' => {
            string_value: '3.14159',
            data_type: 'Number'
          }
        }
      )

      poll_queues_until { worker.received_attributes.size >= 1 }

      attrs = worker.received_attributes.first
      expect(attrs['IntValue']&.string_value).to eq '42'
      expect(attrs['FloatValue']&.string_value).to eq '3.14159'
    end
  end

  describe 'Binary attributes' do
    it 'receives binary message attributes' do
      worker = create_attribute_worker(queue_name)
      worker.received_attributes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
      binary_data = 'binary data content'.b

      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'binary-attr-test',
        message_attributes: {
          'BinaryData' => {
            binary_value: binary_data,
            data_type: 'Binary'
          }
        }
      )

      poll_queues_until { worker.received_attributes.size >= 1 }

      attrs = worker.received_attributes.first
      expect(attrs['BinaryData']&.binary_value).to eq binary_data
    end
  end

  describe 'Multiple attribute types' do
    it 'receives mixed attribute types in single message' do
      worker = create_attribute_worker(queue_name)
      worker.received_attributes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'mixed-attr-test',
        message_attributes: {
          'StringAttr' => {
            string_value: 'text-value',
            data_type: 'String'
          },
          'NumberAttr' => {
            string_value: '100',
            data_type: 'Number'
          },
          'BinaryAttr' => {
            binary_value: 'bytes'.b,
            data_type: 'Binary'
          }
        }
      )

      poll_queues_until { worker.received_attributes.size >= 1 }

      attrs = worker.received_attributes.first
      expect(attrs.keys.size).to eq 3
      expect(attrs['StringAttr']&.data_type).to eq 'String'
      expect(attrs['NumberAttr']&.data_type).to eq 'Number'
      expect(attrs['BinaryAttr']&.data_type).to eq 'Binary'
    end
  end

  describe 'Attribute limits' do
    it 'handles maximum 10 attributes' do
      worker = create_attribute_worker(queue_name)
      worker.received_attributes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      attributes = {}
      10.times do |i|
        attributes["Attr#{i}"] = {
          string_value: "value-#{i}",
          data_type: 'String'
        }
      end

      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'max-attrs-test',
        message_attributes: attributes
      )

      poll_queues_until { worker.received_attributes.size >= 1 }

      attrs = worker.received_attributes.first
      expect(attrs.keys.size).to eq 10
    end
  end

  describe 'System attributes' do
    it 'receives system attributes like ApproximateReceiveCount' do
      worker = create_system_attribute_worker(queue_name)
      worker.received_system_attributes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'system-attr-test'
      )

      poll_queues_until { worker.received_system_attributes.size >= 1 }

      sys_attrs = worker.received_system_attributes.first
      expect(sys_attrs['ApproximateReceiveCount']).to eq '1'
      expect(sys_attrs['SentTimestamp']).not_to be_nil
    end
  end

  describe 'Custom type attributes' do
    it 'handles custom type suffixes' do
      worker = create_attribute_worker(queue_name)
      worker.received_attributes = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'custom-type-test',
        message_attributes: {
          'UserId' => {
            string_value: 'user-123',
            data_type: 'String.UUID'
          },
          'Temperature' => {
            string_value: '98.6',
            data_type: 'Number.Fahrenheit'
          }
        }
      )

      poll_queues_until { worker.received_attributes.size >= 1 }

      attrs = worker.received_attributes.first
      expect(attrs['UserId']&.data_type).to eq 'String.UUID'
      expect(attrs['Temperature']&.data_type).to eq 'Number.Fahrenheit'
    end
  end

  describe 'Attribute-based routing' do
    it 'allows workers to filter based on attributes' do
      worker = create_filtering_worker(queue_name)
      worker.processed_messages = []
      worker.skipped_messages = []

      queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

      # Send message with priority attribute
      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'high-priority',
        message_attributes: {
          'Priority' => { string_value: 'high', data_type: 'String' }
        }
      )

      # Send message without priority
      Shoryuken::Client.sqs.send_message(
        queue_url: queue_url,
        message_body: 'no-priority'
      )

      poll_queues_until { worker.processed_messages.size + worker.skipped_messages.size >= 2 }

      expect(worker.processed_messages).to include('high-priority')
      expect(worker.skipped_messages).to include('no-priority')
    end
  end

  private

  def create_attribute_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_attributes
      end

      shoryuken_options auto_delete: true, batch: false

      def perform(sqs_msg, body)
        self.class.received_attributes ||= []
        self.class.received_attributes << sqs_msg.message_attributes
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.received_attributes = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_system_attribute_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_system_attributes
      end

      shoryuken_options auto_delete: true, batch: false

      def perform(sqs_msg, body)
        self.class.received_system_attributes ||= []
        self.class.received_system_attributes << sqs_msg.attributes
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.received_system_attributes = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_filtering_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :processed_messages, :skipped_messages
      end

      shoryuken_options auto_delete: true, batch: false

      def perform(sqs_msg, body)
        priority = sqs_msg.message_attributes&.dig('Priority', 'string_value')

        if priority == 'high'
          self.class.processed_messages ||= []
          self.class.processed_messages << body
        else
          self.class.skipped_messages ||= []
          self.class.skipped_messages << body
        end
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.processed_messages = []
    worker_class.skipped_messages = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end
end
