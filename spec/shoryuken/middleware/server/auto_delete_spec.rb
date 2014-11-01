require 'spec_helper'

describe Shoryuken::Middleware::Server::AutoDelete do
  let(:sqs_msg)   { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', body: 'test' }
  let(:queue)     { 'default' }
  let(:sqs_queue) { double AWS::SQS::Queue }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  it 'deletes a message' do
    TestWorker.get_shoryuken_options['auto_delete'] = true

    expect(sqs_queue).to receive(:batch_delete).with(sqs_msg)

    subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
  end

  it 'deletes a batch' do
    TestWorker.get_shoryuken_options['auto_delete'] = true

    sqs_msg2 = double 'SQS msg', body: 'test'
    sqs_msg3 = double 'SQS msg', body: 'test'

    sqs_msgs = [sqs_msg, sqs_msg2, sqs_msg3]

    expect(sqs_queue).to receive(:batch_delete).with(*sqs_msgs)

    subject.call(TestWorker.new, queue, sqs_msgs, [sqs_msg.body, sqs_msg2.body, sqs_msg3.body]) {}
  end

  it 'does not delete a message' do
    TestWorker.get_shoryuken_options['auto_delete'] = false

    expect(sqs_queue).to_not receive(:batch_delete)

    subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
  end

  context 'when exception' do
    it 'does not delete a message' do
      expect(sqs_queue).to_not receive(:batch_delete)

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise }
      }.to raise_error
    end
  end
end
