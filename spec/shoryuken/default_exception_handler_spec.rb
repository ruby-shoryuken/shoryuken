require 'spec_helper'

RSpec.describe Shoryuken::DefaultExceptionHandler do
  class CustomErrorHandler
    extend Shoryuken::Util

    def self.call(_ex, queue, _msg)
      logger.error("#{queue} failed to process the message")
    end
  end

  before do
    Shoryuken.worker_executor = Shoryuken::Worker::InlineExecutor
    allow(manager).to receive(:async).and_return(manager)
    allow(manager).to receive(:real_thread)
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  after do
    Shoryuken.worker_executor = Shoryuken::Worker::DefaultExecutor
  end

  let(:manager) { double Shoryuken::Manager }
  let(:sqs_queue) { double Shoryuken::Queue, visibility_timeout: 30 }
  let(:queue) { 'default' }

  let(:sqs_msg) do
    double(
      Shoryuken::Message,
      queue_url: queue,
      body: 'test',
      message_attributes: {},
      message_id: SecureRandom.uuid,
      receipt_handle: SecureRandom.uuid
    )
  end

  subject { Shoryuken::Processor.new(queue, sqs_msg) }

  context 'with default handler' do
    before do
      Shoryuken.exception_handlers = described_class
    end

    it 'logs an error message' do
      expect(Shoryuken::Logging.logger).to receive(:error).twice

      allow_any_instance_of(TestWorker).to receive(:perform).and_raise(StandardError, 'error')
      allow(sqs_msg).to receive(:body)

      expect { subject.process }.to raise_error(StandardError)
    end
  end

  context 'with custom handler' do
    before do
      Shoryuken.exception_handlers = [described_class, CustomErrorHandler]
    end

    it 'logs default and custom error messages' do
      expect(Shoryuken::Logging.logger).to receive(:error).twice
      expect(Shoryuken::Logging.logger).to receive(:error).with('default failed to process the message').once

      allow_any_instance_of(TestWorker).to receive(:perform).and_raise(StandardError, 'error')
      allow(sqs_msg).to receive(:body)

      expect { subject.process }.to raise_error(StandardError)
    end
  end
end
