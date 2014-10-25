require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/fetcher'

describe Shoryuken::Fetcher do
  let(:manager)   { double Shoryuken::Manager }
  let(:sqs_queue) { double 'sqs_queue' }
  let(:queue)     { 'default' }
  let(:sqs_msg)   { double 'SQS msg'}

  subject { described_class.new(manager) }

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end


  describe '#fetch' do
    it 'calls pause when no message' do
      allow(sqs_queue).to receive(:receive_message).with(limit: 1).and_return([])

      expect(manager).to receive(:pause_queue!).with(queue)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue, 1)
    end

    it 'assigns messages' do
      allow(sqs_queue).to receive(:receive_message).with(limit: 5).and_return(sqs_msg)

      expect(manager).to receive(:rebalance_queue_weight!).with(queue)
      expect(manager).to receive(:assign).with(queue, sqs_msg)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue, 5)
    end

    it 'assigns messages in batch' do
      TestWorker.get_shoryuken_options['batch'] = true

      allow(sqs_queue).to receive(:receive_message).with(limit: described_class::FETCH_LIMIT).and_return(sqs_msg)

      expect(manager).to receive(:rebalance_queue_weight!).with(queue)
      expect(manager).to receive(:assign).with(queue, [sqs_msg])
      expect(manager).to receive(:dispatch)

      subject.fetch(queue, 5)
    end
  end
end
