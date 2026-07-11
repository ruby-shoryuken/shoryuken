# frozen_string_literal: true

# rubocop:disable /BlockLength, Metrics/
RSpec.describe Shoryuken::Middleware::Server::ExponentialBackoffRetry do
  let(:queue)     { 'default' }
  let(:sqs_queue) { double Shoryuken::Queue }
  let(:sqs_msg)   {
    double Shoryuken::Message, queue_url: queue, body: 'test', receipt_handle: SecureRandom.uuid,
                               attributes: { 'ApproximateReceiveCount' => 1 }, message_id: SecureRandom.uuid
  }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  context 'when batch worker' do
    it 'yields' do
      expect { |b| subject.call(TestWorker.new, nil, [], nil, &b) }.to yield_control
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

      it 'keeps reusing the last interval for far-later attempts (does not give up)' do
        TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]

        allow(sqs_msg).to receive(:attributes) { { 'ApproximateReceiveCount' => 10 } }
        allow(sqs_msg).to receive(:queue) { sqs_queue }
        expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 1800)

        expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
      end
    end

    context 'and the exception is non-retryable' do
      it 're-raises so NonRetryableException can delete the message' do
        TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]
        TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [ArgumentError]

        expect(sqs_msg).not_to receive(:change_visibility)

        expect {
          subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise ArgumentError, 'permanently invalid' }
        }.to raise_error(ArgumentError, 'permanently invalid')
      end

      it 're-raises when a non_retryable_exceptions lambda returns true' do
        TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]
        TestWorker.get_shoryuken_options['non_retryable_exceptions'] = ->(e) { e.message.include?('permanent') }

        expect(sqs_msg).not_to receive(:change_visibility)

        expect {
          subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'permanent failure' }
        }.to raise_error(RuntimeError, 'permanent failure')
      end

      it 'still retries when a non_retryable_exceptions lambda returns false' do
        TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]
        TestWorker.get_shoryuken_options['non_retryable_exceptions'] = ->(e) { e.message.include?('permanent') }

        allow(sqs_msg).to receive(:queue) { sqs_queue }
        expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 300)

        expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'transient failure' } }
          .not_to raise_error
      end

      it 'still retries exceptions not in the non-retryable list' do
        TestWorker.get_shoryuken_options['retry_intervals'] = [300, 1800]
        TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [ArgumentError]

        allow(sqs_msg).to receive(:queue) { sqs_queue }
        expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 300)

        expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'transient failure' } }
          .not_to raise_error
      end
    end

    it 'limits the visibility timeout to 12 hours' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [86_400]

      allow(sqs_msg).to receive(:queue) { sqs_queue }
      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: 43_198)

      expect { subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'failed' } }.not_to raise_error
    end

    it 'never sets a negative visibility timeout for jobs longer than the SQS ceiling' do
      started_at = Time.now - 43_300 # ran longer than the 12h SQS maximum

      expect(subject.send(:next_visibility_timeout, 300, started_at)).to eq(0)
    end

    it 'does not mask the original error when rescheduling fails' do
      TestWorker.get_shoryuken_options['retry_intervals'] = [300]

      # e.g. an expired receipt handle - change_visibility raises
      allow(sqs_msg).to receive(:change_visibility).and_raise(StandardError, 'visibility boom')

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise 'original worker error' }
      }.to raise_error(RuntimeError, 'original worker error')
    end
  end
end
