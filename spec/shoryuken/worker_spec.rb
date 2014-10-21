require 'spec_helper'

describe 'Shoryuken::Worker' do
  let(:sqs_queue) { double 'SQS Queue' }
  let(:queue)     { 'uppercut' }

  class UppercutWorker
    include Shoryuken::Worker

    shoryuken_options queue: 'uppercut'
  end

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  describe '.perform_async' do
    it 'enqueues a message' do
      expect(sqs_queue).to receive(:send_message).with('test', {})

      UppercutWorker.perform_async('test')
    end

    it 'enqueues a message with options' do
      expect(sqs_queue).to receive(:send_message).with('test2', delay_seconds: 60)

      UppercutWorker.perform_async('test2', delay_seconds: 60)
    end
  end

  describe '.shoryuken_options' do
    it 'registers a worker' do
      expect(Shoryuken.workers['uppercut']).to eq UppercutWorker
    end

    it 'accepts a block as queue name' do
      $queue_prefix = 'production'

      class UppercutWorker
        include Shoryuken::Worker

        shoryuken_options queue: ->{ "#{$queue_prefix}_uppercut" }
      end

      expect(Shoryuken.workers['production_uppercut']).to eq UppercutWorker
    end
  end
end
