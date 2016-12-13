require 'spec_helper'

describe Shoryuken::Middleware::Server::AutoDelete do
  let(:queue)     { 'default' }
  let(:sqs_queue) { double Shoryuken::Queue }

  def build_message
    double Shoryuken::Message,
      queue_url: queue,
      body: 'test',
      receipt_handle: SecureRandom.uuid
  end

  let(:sqs_msg) { build_message }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  it 'deletes a message' do
    TestWorker.get_shoryuken_options['auto_delete'] = true

    expect(sqs_queue).to receive(:delete_messages).with(entries: [
      { id: '0', receipt_handle: sqs_msg.receipt_handle }])

    subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
  end

  it 'deletes a batch' do
    TestWorker.get_shoryuken_options['auto_delete'] = true

    sqs_msg2 = build_message
    sqs_msg3 = build_message

    sqs_msgs = [sqs_msg, sqs_msg2, sqs_msg3]

    expect(sqs_queue).to receive(:delete_messages).with(entries: [
      { id: '0', receipt_handle: sqs_msg.receipt_handle },
      { id: '1', receipt_handle: sqs_msg2.receipt_handle },
      { id: '2', receipt_handle: sqs_msg3.receipt_handle }])

    subject.call(TestWorker.new, queue, sqs_msgs, [sqs_msg.body, sqs_msg2.body, sqs_msg3.body]) {}
  end

  it 'does not delete a message' do
    TestWorker.get_shoryuken_options['auto_delete'] = false

    expect(sqs_queue).to_not receive(:delete_messages)

    subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
  end

  context 'when exception' do
    it 'does not delete a message' do
      expect(sqs_queue).to_not receive(:delete_messages)

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' }
      }.to raise_error('failed')
    end
  end
end
