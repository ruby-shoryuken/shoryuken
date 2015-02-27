require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/launcher'

describe Shoryuken::Launcher do
  describe 'Consuming messages', slow: :true do
    before do
      Shoryuken.options[:aws][:receive_message] = { wait_time_seconds: 5 }

      Shoryuken.queues << 'shoryuken'
      Shoryuken.queues << 'shoryuken_command'

      Shoryuken.register_worker 'shoryuken',          StandardWorker
      Shoryuken.register_worker 'shoryuken_command',  CommandWorker

      StandardWorker.received_messages = 0

      Shoryuken.queues.each do |name|
        Shoryuken::Client.queues(name).purge
      end

      # Gives the queues a moment to empty out
      sleep 1
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

    class CommandWorker
      include Shoryuken::Worker

      @@received_messages = 0

      shoryuken_options queue: 'shoryuken_command', auto_delete: true

      def perform(sqs_msg, body)
        @@received_messages = Array(sqs_msg).size
      end

      def self.received_messages
        @@received_messages
      end

      def self.received_messages=(received_messages)
        @@received_messages = received_messages
      end
    end

    class StandardWorker
      include Shoryuken::Worker

      @@received_messages = 0

      shoryuken_options queue: 'shoryuken', auto_delete: true

      def perform(sqs_msg, body)
        @@received_messages = Array(sqs_msg).size
      end

      def self.received_messages
        @@received_messages
      end

      def self.received_messages=(received_messages)
        @@received_messages = received_messages
      end
    end

    it 'consumes as a command worker' do
      CommandWorker.perform_async('Yo')

      poll_queues_until { CommandWorker.received_messages > 0 }

      expect(CommandWorker.received_messages).to eq 1
    end

    it 'consumes a message' do
      StandardWorker.get_shoryuken_options['batch'] = false

      Shoryuken::Client.queues('shoryuken').send_message(message_body: 'Yo')

      poll_queues_until { StandardWorker.received_messages > 0 }

      expect(StandardWorker.received_messages).to eq 1
    end

    it 'consumes a batch' do
      StandardWorker.get_shoryuken_options['batch'] = true

      entries = []
      10.times { entries << { id: SecureRandom.uuid, message_body: 'Yo' } }

      Shoryuken::Client.queues('shoryuken').send_messages(entries: entries)

      # Give the messages a chance to hit the queue so they are all available at the same time
      sleep 2

      poll_queues_until { StandardWorker.received_messages > 0 }

      expect(StandardWorker.received_messages).to eq 10
    end
  end
end
