require 'spec_helper'

describe Shoryuken::Middleware::Server::Timing do
  let(:queue) { 'default' }
  let(:sqs_queue) { double Shoryuken::Queue, visibility_timeout: 60 }

  let(:sqs_msg) do
    double Shoryuken::Message,
      queue_url: queue,
      body: 'test',
      message_id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e'
  end

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  it 'logs timing' do
    expect(Shoryuken.logger).to receive(:info) do |&block|
      expect(block.call).to match(/started at/)
    end
    expect(Shoryuken.logger).to receive(:info) do |&block|
      expect(block.call).to match(/completed in/)
    end

    subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
  end

  context 'when exceeded the `visibility_timeout`' do
    it 'logs exceeded' do
      allow(subject).to receive(:elapsed).and_return(120000)

      expect(Shoryuken.logger).to receive(:info) do |&block|
        expect(block.call).to match(/started at/)
      end
      expect(Shoryuken.logger).to receive(:info) do |&block|
        expect(block.call).to match(/completed in/)
      end
      expect(Shoryuken.logger).to receive(:warn) do |&block|
        expect(block.call).to match('exceeded the queue visibility timeout by 60000 ms')
      end

      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
    end
  end

  context 'when exception' do
    it 'logs failed in' do
      expect(Shoryuken.logger).to receive(:info) do |&block|
        expect(block.call).to match(/started at/)
      end
      expect(Shoryuken.logger).to receive(:info) do |&block|
        expect(block.call).to match(/failed in/)
      end

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise }
      }.to raise_error
    end
  end
end
