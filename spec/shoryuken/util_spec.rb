require 'spec_helper'

describe 'Shoryuken::Util' do
  subject do
    Class.new do
      extend Shoryuken::Util
    end
  end

  describe '#unparse_queues' do
    it 'returns queues and weights' do
      queues = %w[queue1 queue1 queue2 queue3 queue4 queue4 queue4]

      expect(subject.unparse_queues(queues)).to eq([['queue1', 2], ['queue2', 1], ['queue3', 1], ['queue4', 3]])
    end
  end

  describe '#worker_name' do
    let(:sqs_msg) { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', message_attributes: {} }

    it 'returns Shoryuken worker name' do
      expect(subject.worker_name(TestWorker, sqs_msg)).to eq 'TestWorker'
    end

    it 'returns ActiveJob worker name'
  end
end
