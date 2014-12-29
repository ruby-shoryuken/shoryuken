require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/fetcher'

describe Shoryuken::Fetcher do
  let(:manager)    { double Shoryuken::Manager }
  let(:queue)      { double Shoryuken::Queue }
  let(:queue_name) { 'default' }

  let(:sqs_msg) do
    Shoryuken::ReceivedMessage.new(
      queue_name,
      OpenStruct.new(message_id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', body: 'test'))
  end

  subject { described_class.new(manager) }

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(Shoryuken::Client).to receive(:queue).with(queue_name).and_return(queue)
  end


  describe '#fetch' do
    it 'calls pause when no message' do
      allow(queue).to receive(:receive_messages).with(limit: 1, message_attribute_names: ['shoryuken_class']).and_return([])

      expect(manager).to receive(:pause_queue!).with(queue_name)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_name, 1)
    end

    it 'assigns messages' do
      allow(queue).to receive(:receive_messages).with(limit: 5, message_attribute_names: ['shoryuken_class']).and_return(sqs_msg)

      expect(manager).to receive(:rebalance_queue_weight!).with(queue_name)
      expect(manager).to receive(:assign).with(queue_name, sqs_msg)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_name, 5)
    end

    it 'assigns messages in batch' do
      TestWorker.get_shoryuken_options['batch'] = true

      allow(queue).to receive(:receive_messages).with(limit: described_class::FETCH_LIMIT, message_attribute_names: ['shoryuken_class']).and_return(sqs_msg)

      expect(manager).to receive(:rebalance_queue_weight!).with(queue_name)
      expect(manager).to receive(:assign).with(queue_name, [sqs_msg])
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_name, 5)
    end

    context 'when worker not found' do
      let(:queue_name) { 'notfound' }

      it 'ignores batch' do
        allow(queue).to receive(:receive_messages).with(limit: 5, message_attribute_names: ['shoryuken_class']).and_return(sqs_msg)

        expect(manager).to receive(:rebalance_queue_weight!).with(queue_name)
        expect(manager).to receive(:assign).with(queue_name, sqs_msg)
        expect(manager).to receive(:dispatch)

        subject.fetch(queue_name, 5)
      end
    end
  end
end
