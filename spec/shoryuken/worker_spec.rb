require 'spec_helper'

describe 'Shoryuken::Worker' do
  let(:sqs_queue) { double 'SQS Queue' }
  let(:queue)     { 'default' }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  describe '.perform_async' do
    it 'enqueues a message' do
      expect(sqs_queue).to receive(:send_message).with('message', {})

      TestWorker.perform_async('message')
    end

    it 'enqueues a message with options' do
      expect(sqs_queue).to receive(:send_message).with('delayed message', delay_seconds: 60)

      TestWorker.perform_async('delayed message', delay_seconds: 60)
    end
  end

  describe '.shoryuken_options' do
    it 'registers a worker' do
      expect(Shoryuken.workers['default']).to eq TestWorker
    end

    it 'accepts a block as queue name' do
      $queue_prefix = 'production'

      class NewTestWorker
        include Shoryuken::Worker

        shoryuken_options queue: ->{ "#{$queue_prefix}_default" }
      end

      expect(Shoryuken.workers['production_default']).to eq NewTestWorker
    end
  end
end
