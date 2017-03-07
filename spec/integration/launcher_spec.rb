require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/launcher'
require 'securerandom'

RSpec.describe Shoryuken::Launcher do
  describe 'Consuming messages', slow: :true do
    before do
      StandardWorker.received_messages = 0

      queue = "test_shoryuken#{StandardWorker}_#{SecureRandom.uuid}"

      Shoryuken::Client.sqs.create_queue queue_name: queue

      Shoryuken.queues << queue

      StandardWorker.get_shoryuken_options['queue'] = queue

      Shoryuken.register_worker queue, StandardWorker
    end

    after do
      queue_url = Shoryuken::Client.sqs.get_queue_url(
        queue_name: StandardWorker.get_shoryuken_options['queue']
      ).queue_url

      Shoryuken::Client.sqs.delete_queue queue_url: queue_url
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
      subject.run

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

      def perform(sqs_msg, body)
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
