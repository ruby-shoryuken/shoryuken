# frozen_string_literal: true

# This spec tests the Launcher's ability to consume messages from SQS queues,
# including single message consumption, batch consumption, and command workers.

RSpec.describe Shoryuken::Launcher do
  include_context 'localstack'

  describe 'Consuming messages' do
    before do
      StandardWorker.received_messages = 0

      queue = "shoryuken-travis-#{StandardWorker}-#{SecureRandom.uuid}"

      create_test_queue(queue)

      Shoryuken.add_group('default', 1)
      Shoryuken.add_queue(queue, 1, 'default')

      StandardWorker.get_shoryuken_options['queue'] = queue

      Shoryuken.register_worker(queue, StandardWorker)
    end

    after do
      delete_test_queue(StandardWorker.get_shoryuken_options['queue'])
    end

    it 'consumes as a command worker' do
      StandardWorker.perform_async('Yo')

      poll_queues { StandardWorker.received_messages > 0 }

      expect(StandardWorker.received_messages).to eq 1
    end

    it 'consumes a message' do
      StandardWorker.get_shoryuken_options['batch'] = false

      Shoryuken::Client.queues(StandardWorker.get_shoryuken_options['queue']).send_message(message_body: 'Yo')

      poll_queues { StandardWorker.received_messages > 0 }

      expect(StandardWorker.received_messages).to eq 1
    end

    it 'consumes a batch' do
      StandardWorker.get_shoryuken_options['batch'] = true

      entries = 10.times.map { |i| { id: SecureRandom.uuid, message_body: i.to_s } }

      Shoryuken::Client.queues(StandardWorker.get_shoryuken_options['queue']).send_messages(entries: entries)

      # Give the messages a chance to hit the queue so they are all available at the same time
      sleep 2

      poll_queues { StandardWorker.received_messages > 0 }

      expect(StandardWorker.received_messages).to be > 1
    end

    # Local poll method using subject (the Launcher)
    def poll_queues
      subject.start

      Timeout.timeout(10) do
        sleep 0.5 until yield
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
