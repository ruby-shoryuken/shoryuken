require 'spec_helper'

describe Shoryuken::Middleware::Server::AutoRetry do
  let(:queue)     { 'default' }
  let(:sqs_queue) { double Aws::SQS::Queue,   visibility_timeout: 30 }
  let(:sqs_msg)   { double Aws::SQS::Message, queue_url: queue, body: 'test', receipt_handle: SecureRandom.uuid,
                                              receive_count: 1, id: SecureRandom.uuid }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end
  
  context 'when a job succeeds' do
    it 'does not retry the job' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]
  
      expect(sqs_msg).not_to receive(:visibility_timeout=)
  
      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
    end
  end

  context 'when a job throws an exception' do

    it 'does not retry the job by default' do
      expect(sqs_msg).not_to receive(:visibility_timeout=)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise } }.to raise_error
    end

    it 'does not retry the job if :retry_intervals is empty' do
      TestWorker.get_shoryuken_options['retry_intervals'] = []
      
      expect(sqs_msg).not_to receive(:visibility_timeout=)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise } }.to raise_error
    end

    it 'retries the job if :retry_intervals is non-empty' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]
      
      allow(sqs_msg).to receive(:queue){ sqs_queue }
      expect(sqs_msg).to receive(:visibility_timeout=).with(300)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise } }.not_to raise_error
    end

    it 'retries the job with exponential backoff' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]
      
      allow(sqs_msg).to receive(:receive_count){ 2 }
      allow(sqs_msg).to receive(:queue){ sqs_queue }
      expect(sqs_msg).to receive(:visibility_timeout=).with(1800)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise } }.not_to raise_error
    end

    it 'uses the last retry interval when :receive_count exceeds the size of :retry_intervals' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]
      
      allow(sqs_msg).to receive(:receive_count){ 3 }
      allow(sqs_msg).to receive(:queue){ sqs_queue }
      expect(sqs_msg).to receive(:visibility_timeout=).with(1800)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise } }.not_to raise_error
    end

    it 'limits the visibility timeout to 12 hours' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [86400]
      
      allow(sqs_msg).to receive(:queue){ sqs_queue }
      expect(sqs_msg).to receive(:visibility_timeout=).with(43200)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise } }.not_to raise_error
    end
  end
end
