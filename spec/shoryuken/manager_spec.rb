require 'spec_helper'

describe Shoryuken::Manager do
  let(:fetcher) { Shoryuken::Fetcher.new(manager) }
  let(:manager) { described_class.new($config) }


  before do
    manager.fetcher = fetcher
  end

  describe 'Consuming messages', slow: :true do
    before do
      $cool_worker_messages = []
    end

    class CoolWorker
      include Shoryuken::Worker

      def perform(sqs_msg, cool_message)
        $cool_worker_messages << cool_message

        sqs_msg.delete
      end
    end

    it 'consumes a message' do
      CoolWorker.perform_async('Yo')

      manager.start

      10.times do
        break unless $cool_worker_messages.empty?
        sleep 1
      end

      manager.stop

      expect($cool_worker_messages.first).to eq 'Yo'
    end
  end
end
