require 'spec_helper'

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
        $received_messages += 1
      end
    end

    it 'consumes a message' do
      Shoryuken::Client.queues('shoryuken').send_message('Yo')

      10.times do
        break if $received_messages > 0
        sleep 0.5
      end

      expect($received_messages).to eq 1
    end
  end
end
