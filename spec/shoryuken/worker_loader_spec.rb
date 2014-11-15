require 'spec_helper'

describe Shoryuken::WorkerLoader do
  let(:queue)   { 'default' }
  let(:sqs_msg) { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', body: 'test', message_attributes: { } }

  describe '.call' do
    it 'returns the worker using `Shoryuken.workers`' do
      expect(described_class.call(queue, sqs_msg)).to be_an_instance_of TestWorker
    end

    context 'when `message_attributes`' do
      let(:sqs_msg) { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', body: 'test', message_attributes: {
        'shoryuken_class' => {
          string_value: TestWorker.to_s,
          data_type: 'String'
        }
      } }

      it 'returns the worker using `message_attributes`' do
        Shoryuken.workers.clear

        expect(described_class.call(queue, sqs_msg)).to be_an_instance_of TestWorker
      end
    end
  end
end
