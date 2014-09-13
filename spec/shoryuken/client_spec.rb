require 'spec_helper'

describe Shoryuken::Client do
  let(:sqs)              { double 'SQS' }
  let(:queue_collection) { double 'Queues Collection' }
  let(:queue)            { double 'Queue' }

  before do
    allow(described_class).to receive(:sqs).and_return(sqs)
    allow(sqs).to receive(:queues).and_return(queue_collection)
  end

  describe '.queues' do
    it 'memoizes queues' do
      expect(queue_collection).to receive(:named).once.with('yo').and_return(queue)

      expect(Shoryuken::Client.queues('yo')).to eq queue
      expect(Shoryuken::Client.queues('yo')).to eq queue
    end
  end
end
