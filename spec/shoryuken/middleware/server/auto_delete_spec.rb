require 'spec_helper'

describe Shoryuken::Middleware::Server::AutoDelete do
  let(:sqs_msg) { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', body: 'test' }
  let(:queue)   { 'default' }

  it 'deletes a message' do
    TestWorker.get_shoryuken_options['delete'] = true

    expect(sqs_msg).to receive(:delete)

    subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
  end

  it 'deletes a batch' do
    TestWorker.get_shoryuken_options['delete'] = true

    sqs_msg2 = double 'SQS msg', body: 'test'
    sqs_msg3 = double 'SQS msg', body: 'test'

    expect(sqs_msg).to receive(:delete)
    expect(sqs_msg2).to receive(:delete)
    expect(sqs_msg3).to receive(:delete)

    subject.call(TestWorker.new, queue, [sqs_msg, sqs_msg2, sqs_msg3], [sqs_msg.body, sqs_msg2.body, sqs_msg3.body]) {}
  end

  it 'does not delete a message' do
    TestWorker.get_shoryuken_options['delete'] = false

    expect(sqs_msg).to_not receive(:delete)

    subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
  end

  context 'when exception' do
    it 'does not delete a message' do
      expect(sqs_msg).to_not receive(:delete)

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise }
      }.to raise_error
    end
  end
end
