require 'spec_helper'

describe Shoryuken::Client do
  let(:sqs)              { double 'SQS' }
  let(:queue_collection) { double 'Queues Collection' }
  let(:queue)            { double 'Queue' }
  let(:queue_name)       { 'shoryuken' }

  before do
    allow(described_class).to receive(:sqs).and_return(sqs)
    sqs.stub(queues: queue_collection)
    queue_collection.stub(named: queue)
  end

  describe '.queues' do
    it 'memoizes queues' do
      expect(queue_collection).to receive(:named).once.with(queue_name).and_return(queue)

      expect(Shoryuken::Client.queues(queue_name)).to eq queue
      expect(Shoryuken::Client.queues(queue_name)).to eq queue
    end
  end

  describe '.visibility_timeout' do
    it 'memoizes visibility_timeout' do
      expect(queue_collection).to receive(:named).once.with(queue_name).and_return(queue)

      expect(queue).to receive(:visibility_timeout).once.and_return(30)

      expect(Shoryuken::Client.visibility_timeout(queue_name)).to eq 30
      expect(Shoryuken::Client.visibility_timeout(queue_name)).to eq 30
    end
  end
end
