require 'spec_helper'

# rubocop:disable Metrics/BlockLength, Metrics/BlockDelimiters
RSpec.describe Shoryuken::Middleware::Server::ExponentialBackoffRetry do
  let(:queue)     { 'default' }
  let(:sqs_queue) { double Shoryuken::Queue }
  let(:sqs_msg)   { double Shoryuken::Message, queue_url: queue, body: 'test', receipt_handle: SecureRandom.uuid,
                    attributes: {'ApproximateReceiveCount' => 1}, message_id: SecureRandom.uuid }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  context 'when batch worker' do
    it 'yields' do
      expect { |b| subject.call(nil, nil, [], nil, &b) }.to yield_control
    end
  end

  context 'when no exception' do
    it 'does not retry' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

      expect(sqs_msg).not_to receive(:change_visibility)

      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
    end
  end

  context 'when an error' do
    context "and retry_intervals isn't set" do
      it 'does not retry' do
        expect(sqs_msg).not_to receive(:change_visibility)

        expect {
          subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'Error' }
        }.to raise_error(RuntimeError, 'Error')
      end
    end

    context 'and retry_intervals is a lambda' do
      it 'retries' do
        TestWorker.get_shoryuken_options['retry_intervals'] = ->(_attempts) { 500 }

        allow(sqs_msg).to receive(:queue) { sqs_queue }
        expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 500)

        expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
      end
    end

    context 'and retry_intervals is empty' do
      it 'does not retry' do
        TestWorker.get_shoryuken_options['retry_intervals'] = []

        expect(sqs_msg).not_to receive(:change_visibility)

        expect {
          subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'Error' }
        }.to raise_error(RuntimeError, 'Error')
      end
    end

    it 'uses first interval ' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

      allow(sqs_msg).to receive(:queue) { sqs_queue }
      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 300)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
    end

    it 'uses matching interval' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

      allow(sqs_msg).to receive(:attributes) { { 'ApproximateReceiveCount' => 2 } }
      allow(sqs_msg).to receive(:queue) { sqs_queue }
      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 1800)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
    end

    context 'when attempts exceeds retry_intervals' do
      it 'uses last interval' do
        TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

        allow(sqs_msg).to receive(:attributes) { { 'ApproximateReceiveCount' => 3 } }
        allow(sqs_msg).to receive(:queue) { sqs_queue }
        expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 1800)

        expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
      end
    end

    it 'limits the visibility timeout to 12 hours' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [86_400]

      allow(sqs_msg).to receive(:queue) { sqs_queue }
      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 43_198)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
    end
  end
end
