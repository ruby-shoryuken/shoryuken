require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/launcher'

describe Shoryuken::Launcher do
  describe 'Consuming messages', slow: :true do
    before do
      subject.run

      $received_messages = 0
    end

    after do
      subject.stop
    end

    class ShoryukenWorker
      include Shoryuken::Worker

      shoryuken_options queue: 'shoryuken', auto_delete: true

      def perform(sqs_msg)
        $received_messages = Array(sqs_msg).size
      end
    end

    it 'consumes a message' do
      ShoryukenWorker.get_shoryuken_options['batch'] = false

      Shoryuken::Client.queues('shoryuken').send_message('Yo')

      10.times do
        break if $received_messages > 0
        sleep 0.2
      end

      expect($received_messages).to eq 1
    end

    it 'consumes a batch' do
      ShoryukenWorker.get_shoryuken_options['batch'] = true

      Shoryuken::Client.queues('shoryuken').batch_send *(['Yo'] * 10)

      10.times do
        break if $received_messages > 0
        sleep 0.2
      end

      # the fetch result is uncertain, should be greater than 1, but hard to tell the exact size
      expect($received_messages).to be > 1
    end
  end
end
