require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/launcher'

describe Shoryuken::Launcher do
  describe 'Consuming messages', slow: :true do
    before do
      Shoryuken.options[:aws] ||= {}
      Shoryuken.options[:aws][:receive_message] ||= {}
      Shoryuken.options[:aws][:receive_message][:wait_time_seconds] = 5

      Shoryuken.queues << 'shoryuken'
      Shoryuken.queues << 'shoryuken_command'

      Shoryuken.register_worker 'shoryuken',          StandardWorker
      Shoryuken.register_worker 'shoryuken_command',  CommandWorker

      subject.run

      StandardWorker.received_messages = 0
    end

    after { subject.stop }

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

      10.times do
        break if CommandWorker.received_messages > 0
        sleep 1
      end

      expect(CommandWorker.received_messages).to eq 1
    end

    it 'consumes a message' do
      StandardWorker.get_shoryuken_options['batch'] = false

      Shoryuken::Client.queues('shoryuken').send_message('Yo')

      10.times do
        break if StandardWorker.received_messages > 0
        sleep 1
      end

      expect(StandardWorker.received_messages).to eq 1
    end

    it 'consumes a batch' do
      StandardWorker.get_shoryuken_options['batch'] = true

      Shoryuken::Client.queues('shoryuken').batch_send *(['Yo'] * 10)

      10.times do
        break if StandardWorker.received_messages > 0
        sleep 1
      end

      # the fetch result is uncertain, should be greater than 1, but hard to tell the exact size
      expect(StandardWorker.received_messages).to be > 1
    end
  end
end
