require 'spec_helper'

describe Shoryuken::Middleware::Server::ExponentialBackoffRetry do
  let(:queue)     { 'default' }
  let(:sqs_queue) { double Shoryuken::Queue }
  let(:sqs_msg)   { double Shoryuken::Message, queue_url: queue, body: 'test', receipt_handle: SecureRandom.uuid,
                    attributes: {'ApproximateReceiveCount' => 1}, message_id: SecureRandom.uuid }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  context 'when a job succeeds' do
    it 'does not retry the job' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

      expect(sqs_msg).not_to receive(:change_visibility)

      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
    end
  end

  context 'when a job throws an exception' do

    it 'does not retry the job by default' do
      expect(sqs_msg).not_to receive(:change_visibility)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.to raise_error('failed')
    end

    it 'does not retry the job if :retry_intervals is empty' do
      TestWorker.get_shoryuken_options['retry_intervals'] = []

      expect(sqs_msg).not_to receive(:change_visibility)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.to raise_error('failed')
    end

    it 'retries the job if :retry_intervals is non-empty' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

      allow(sqs_msg).to receive(:queue){ sqs_queue }
      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 300)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
    end

    it 'retries the job with exponential backoff' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

      allow(sqs_msg).to receive(:attributes){ {'ApproximateReceiveCount' => 2 } }
      allow(sqs_msg).to receive(:queue){ sqs_queue }
      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 1800)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
    end

    it 'uses the last retry interval when :receive_count exceeds the size of :retry_intervals' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

      allow(sqs_msg).to receive(:attributes){ {'ApproximateReceiveCount' => 3 } }
      allow(sqs_msg).to receive(:queue){ sqs_queue }
      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 1800)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
    end

    it 'limits the visibility timeout to 12 hours from receipt of message' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [86400]

      allow(sqs_msg).to receive(:queue){ sqs_queue }
      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 43198)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
    end
  end
end
