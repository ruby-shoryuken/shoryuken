require 'spec_helper'

describe Shoryuken::Client do
  let(:sqs)              { double 'SQS' }
  let(:queue_collection) { double 'Queues Collection' }
  let(:sqs_queue)        { double 'SQS Queue' }
  let(:queue)            { 'shoryuken' }

  before do
    allow(described_class).to receive(:sqs).and_return(sqs)
    allow(sqs).to receive(:queues).and_return(queue_collection)
    allow(queue_collection).to receive(:named).and_return(sqs_queue)
  end

  describe '.queues' do
    it 'memoizes queues' do
      expect(queue_collection).to receive(:named).once.with(queue).and_return(sqs_queue)

      expect(Shoryuken::Client.queues(queue)).to eq sqs_queue
      expect(Shoryuken::Client.queues(queue)).to eq sqs_queue
    end
  end

  describe '.send_message' do
    it 'enqueues a message' do
      expect(sqs_queue).to receive(:send_message).with('test', {})

      described_class.send_message(queue, 'test')
    end

    it 'enqueues a message with options' do
      expect(sqs_queue).to receive(:send_message).with('test2', delay_seconds: 60)

      described_class.send_message(queue, 'test2', delay_seconds: 60)
    end

    it 'parsers as JSON by default' do
      msg = { field: 'test', other_field: 'other' }

      expect(sqs_queue).to receive(:send_message).with(JSON.dump(msg), {})

      described_class.send_message(queue, msg)
    end

    it 'parsers as JSON by default and keep the options' do
      msg = { field: 'test', other_field: 'other' }

      expect(sqs_queue).to receive(:send_message).with(JSON.dump(msg), { delay_seconds:  60 })

      described_class.send_message(queue, msg, delay_seconds: 60)
    end
  end

  describe '.visibility_timeout' do
    it 'memoizes visibility_timeout' do
      expect(sqs_queue).to receive(:visibility_timeout).once.and_return(30)

      expect(Shoryuken::Client.visibility_timeout(queue)).to eq 30
      expect(Shoryuken::Client.visibility_timeout(queue)).to eq 30
    end
  end
end
