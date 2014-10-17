require 'spec_helper'

describe Shoryuken::Client do
  let(:sqs)              { double 'SQS' }
  let(:queue_collection) { double 'Queues Collection' }
  let(:sqs_queue)        { double 'Queue' }
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

  describe '.visibility_timeout' do
    it 'memoizes visibility_timeout' do
      expect(sqs_queue).to receive(:visibility_timeout).once.and_return(30)

      expect(Shoryuken::Client.visibility_timeout(queue)).to eq 30
      expect(Shoryuken::Client.visibility_timeout(queue)).to eq 30
    end
  end
end
