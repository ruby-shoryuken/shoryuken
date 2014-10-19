require 'spec_helper'

describe Shoryuken::Middleware::Server::Delete do
  let(:sqs_msg) { double 'SQS msg' }

  before do
    DeleteWorker.get_shoryuken_options['delete'] = true
  end

  class DeleteWorker
    include Shoryuken::Worker

    shoryuken_options queue: 'delete', delete: true

    def perform; end
  end

  it 'deletes a message' do
    expect(sqs_msg).to receive(:delete)

    subject.call(DeleteWorker.new, 'delete', sqs_msg) {}
  end

  it 'deletes a batch' do
    sqs_msg2 = double
    sqs_msg3 = double

    expect(sqs_msg).to receive(:delete)
    expect(sqs_msg2).to receive(:delete)
    expect(sqs_msg3).to receive(:delete)

    subject.call(DeleteWorker.new, 'delete', [sqs_msg, sqs_msg2, sqs_msg3]) {}
  end

  it 'does not delete a message' do
    DeleteWorker.get_shoryuken_options['delete'] = false

    expect(sqs_msg).to_not receive(:delete)

    subject.call(DeleteWorker.new, 'delete', sqs_msg) {}
  end

  context 'when exception' do
    it 'does not delete a message' do
      expect(sqs_msg).to_not receive(:delete)

      expect {
        subject.call(DeleteWorker.new, 'delete', sqs_msg) { raise }
      }.to raise_error
    end
  end
end
