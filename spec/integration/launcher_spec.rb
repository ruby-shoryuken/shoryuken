require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/launcher'
require 'securerandom'

RSpec.describe Shoryuken::Launcher do
  let(:sqs_client) do
    Aws::SQS::Client.new(
      region: 'us-east-1',
      endpoint: 'http://localhost:5000',
      access_key_id: 'fake',
      secret_access_key: 'fake'
    )
  end

  let(:executor) do
    # We can't use Concurrent.global_io_executor in these tests since once you
    # shut down a thread pool, you can't start it back up. Instead, we create
    # one new thread pool executor for each spec. We use a new
    # CachedThreadPool, since that most closely resembles
    # Concurrent.global_io_executor
    Concurrent::CachedThreadPool.new auto_terminate: true
  end

  describe 'Consuming messages' do
    before do
      Aws.config[:stub_responses] = false

      allow(Shoryuken).to receive(:launcher_executor).and_return(executor)

      Shoryuken.configure_client do |config|
        config.sqs_client = sqs_client
      end

      Shoryuken.configure_server do |config|
        config.sqs_client = sqs_client
      end

      StandardWorker.received_messages = 0

      queue = "shoryuken-travis-#{StandardWorker}-#{SecureRandom.uuid}"

      Shoryuken::Client.sqs.create_queue(queue_name: queue)

      Shoryuken.add_group('default', 1)
      Shoryuken.add_queue(queue, 1, 'default')

      StandardWorker.get_shoryuken_options['queue'] = queue

      Shoryuken.register_worker(queue, StandardWorker)
    end

    after do
      Aws.config[:stub_responses] = true
    end

    it 'consumes as a command worker' do
      StandardWorker.perform_async('Yo')

      poll_queues_until { StandardWorker.received_messages > 0 }

      expect(StandardWorker.received_messages).to eq 1
    end

    it 'consumes a message' do
      StandardWorker.get_shoryuken_options['batch'] = false

      Shoryuken::Client.queues(StandardWorker.get_shoryuken_options['queue']).send_message(message_body: 'Yo')

      poll_queues_until { StandardWorker.received_messages > 0 }

      expect(StandardWorker.received_messages).to eq 1
    end

    it 'consumes a batch' do
      StandardWorker.get_shoryuken_options['batch'] = true

      entries = 10.times.map { |i| { id: SecureRandom.uuid, message_body: i.to_s } }

      Shoryuken::Client.queues(StandardWorker.get_shoryuken_options['queue']).send_messages(entries: entries)

      # Give the messages a chance to hit the queue so they are all available at the same time
      sleep 2

      poll_queues_until { StandardWorker.received_messages > 0 }

      expect(StandardWorker.received_messages).to be > 1
    end

    def poll_queues_until
      subject.start

      Timeout::timeout(10) do
        begin
          sleep 0.5
        end until yield
      end
    ensure
      subject.stop
    end

    class StandardWorker
      include Shoryuken::Worker

      @@received_messages = 0

      shoryuken_options auto_delete: true

      def perform(sqs_msg, _body)
        @@received_messages += Array(sqs_msg).size
      end

      def self.received_messages
        @@received_messages
      end

      def self.received_messages=(received_messages)
        @@received_messages = received_messages
      end
    end
  end
end
