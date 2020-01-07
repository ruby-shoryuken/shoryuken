require 'spec_helper'

RSpec.describe Shoryuken::Middleware::Server::Timing do
  let(:queue) { 'default' }
  let(:sqs_queue) { double Shoryuken::Queue, visibility_timeout: 60 }

  let(:sqs_msg) do
    double(
      Shoryuken::Message,
      queue_url: queue,
      body: 'test',
      message_id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e'
    )
  end

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  it 'logs timing' do
    expect(sqs_msg).to receive(:become_available_at).and_return(Time.now + 1_000)

    expect(Shoryuken.logger).to receive(:info) do |&block|
      expect(block.call).to match(/started at/)
    end
    expect(Shoryuken.logger).to receive(:info) do |&block|
      expect(block.call).to match(/completed in/)
    end

    subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
  end

  context 'when exceeded the `visibility_timeout`' do
    before do
      @started_at = Time.now 
      @ended_at = @started_at + 120
    end

    it 'logs exceeded' do
      expect(Time).to receive(:now).and_return(@started_at, @ended_at)
      expect(sqs_msg).to receive(:become_available_at).and_return(@ended_at - 30).twice

      expect(Shoryuken.logger).to receive(:info) do |&block|
        expect(block.call).to match(/started at/)
      end
      expect(Shoryuken.logger).to receive(:info) do |&block|
        expect(block.call).to match(/completed in/)
      end
      expect(Shoryuken.logger).to receive(:warn) do |&block|
        expect(block.call).to match('exceeded the message visibility timeout by 30000.0 ms')
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
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'Error' }
      }.to raise_error(RuntimeError, 'Error')
    end
  end
end
