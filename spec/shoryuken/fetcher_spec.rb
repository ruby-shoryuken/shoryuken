require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/fetcher'

describe Shoryuken::Fetcher do
  let(:manager)   { double Shoryuken::Manager }
  let(:sqs_queue) { double 'sqs_queue' }
  let(:queue)     { 'default' }
  let(:sqs_msg)   { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', body: 'test' }

  subject { described_class.new(manager) }

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end


  describe '#fetch' do
    it 'calls pause when no message' do
      allow(sqs_queue).to receive(:receive_message).with(limit: 1, message_attribute_names: ['shoryuken_class']).and_return([])

      expect(manager).to receive(:pause_queue!).with(queue)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue, 1)
    end

    it 'assigns messages' do
      allow(sqs_queue).to receive(:receive_message).with(limit: 5, message_attribute_names: ['shoryuken_class']).and_return(sqs_msg)

      expect(manager).to receive(:rebalance_queue_weight!).with(queue)
      expect(manager).to receive(:assign).with(queue, sqs_msg)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue, 5)
    end

    it 'assigns messages in batch' do
      TestWorker.get_shoryuken_options['batch'] = true

      allow(sqs_queue).to receive(:receive_message).with(limit: described_class::FETCH_LIMIT, message_attribute_names: ['shoryuken_class']).and_return(sqs_msg)

      expect(manager).to receive(:rebalance_queue_weight!).with(queue)
      expect(manager).to receive(:assign).with(queue, [sqs_msg])
      expect(manager).to receive(:dispatch)

      subject.fetch(queue, 5)
    end

    context 'when worker not found' do
      let(:queue) { 'notfound' }

      it 'ignores batch' do
        allow(sqs_queue).to receive(:receive_message).with(limit: 5, message_attribute_names: ['shoryuken_class']).and_return(sqs_msg)

        expect(manager).to receive(:rebalance_queue_weight!).with(queue)
        expect(manager).to receive(:assign).with(queue, sqs_msg)
        expect(manager).to receive(:dispatch)

        subject.fetch(queue, 5)
      end
    end
  end
end
