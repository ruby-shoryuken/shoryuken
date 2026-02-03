# frozen_string_literal: true

RSpec.describe Shoryuken::Middleware::Server::NonRetryableException do
  let(:queue)     { 'default' }
  let(:sqs_queue) { double Shoryuken::Queue }

  def build_message
    double Shoryuken::Message,
           queue_url: queue,
           body: 'test',
           message_id: SecureRandom.uuid,
           receipt_handle: SecureRandom.uuid
  end

  let(:sqs_msg) { build_message }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  context 'when non_retryable_exceptions is not configured' do
    it 're-raises the exception' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = nil

      expect(sqs_queue).not_to receive(:delete_messages)

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise StandardError, 'test error' }
      }.to raise_error(StandardError, 'test error')
    end
  end

  context 'when exception is not in non_retryable_exceptions list' do
    it 're-raises the exception' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [ArgumentError]

      expect(sqs_queue).not_to receive(:delete_messages)

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise StandardError, 'test error' }
      }.to raise_error(StandardError, 'test error')
    end
  end

  context 'when exception is in non_retryable_exceptions list' do
    it 'deletes the message and does not re-raise' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [StandardError]

      expect(sqs_queue).to receive(:delete_messages).with(entries: [
                                                           { id: '0', receipt_handle: sqs_msg.receipt_handle }
                                                         ])

      expect(Shoryuken.logger).to receive(:warn) do |&block|
        expect(block.call).to match(/Non-retryable exception StandardError/)
      end

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise StandardError, 'test error' }
      }.not_to raise_error
    end

    it 'logs the exception backtrace in debug mode' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [StandardError]

      error = StandardError.new('test error')
      error.set_backtrace(['backtrace line 1', 'backtrace line 2'])

      allow(sqs_queue).to receive(:delete_messages)

      expect(Shoryuken.logger).to receive(:warn)
      expect(Shoryuken.logger).to receive(:debug) do |&block|
        expect(block.call).to eq("backtrace line 1\nbacktrace line 2")
      end

      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise error }
    end

    it 'handles multiple exception classes' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [ArgumentError, StandardError]

      expect(sqs_queue).to receive(:delete_messages).with(entries: [
                                                           { id: '0', receipt_handle: sqs_msg.receipt_handle }
                                                         ])

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise ArgumentError, 'test error' }
      }.not_to raise_error
    end

    it 'handles custom exception classes' do
      custom_error = Class.new(StandardError)
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [custom_error]

      expect(sqs_queue).to receive(:delete_messages).with(entries: [
                                                           { id: '0', receipt_handle: sqs_msg.receipt_handle }
                                                         ])

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise custom_error, 'test error' }
      }.not_to raise_error
    end
  end

  context 'with batch messages' do
    it 'deletes all messages in the batch' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [StandardError]

      sqs_msg2 = build_message
      sqs_msg3 = build_message
      sqs_msgs = [sqs_msg, sqs_msg2, sqs_msg3]

      expect(sqs_queue).to receive(:delete_messages).with(entries: [
                                                           { id: '0', receipt_handle: sqs_msg.receipt_handle },
                                                           { id: '1', receipt_handle: sqs_msg2.receipt_handle },
                                                           { id: '2', receipt_handle: sqs_msg3.receipt_handle }
                                                         ])

      expect(Shoryuken.logger).to receive(:warn) do |&block|
        expect(block.call).to match(/Non-retryable exception StandardError/)
        expect(block.call).to match(/#{sqs_msg.message_id}/)
        expect(block.call).to match(/#{sqs_msg2.message_id}/)
        expect(block.call).to match(/#{sqs_msg3.message_id}/)
      end

      expect {
        subject.call(TestWorker.new, queue, sqs_msgs, [sqs_msg.body, sqs_msg2.body, sqs_msg3.body]) do
          raise StandardError, 'test error'
        end
      }.not_to raise_error
    end
  end

  context 'when no exception occurs' do
    it 'does not delete the message' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = [StandardError]

      expect(sqs_queue).not_to receive(:delete_messages)

      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) {}
    end
  end

  context 'when using lambda for dynamic classification' do
    it 'calls the lambda with the exception and deletes if lambda returns true' do
      lambda_called = false
      lambda_result = true

      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = lambda do |error|
        lambda_called = true
        expect(error).to be_a(StandardError)
        expect(error.message).to eq('test error')
        lambda_result
      end

      expect(sqs_queue).to receive(:delete_messages).with(entries: [
                                                           { id: '0', receipt_handle: sqs_msg.receipt_handle }
                                                         ])

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise StandardError, 'test error' }
      }.not_to raise_error

      expect(lambda_called).to be true
    end

    it 're-raises if lambda returns false' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = ->(_error) { false }

      expect(sqs_queue).not_to receive(:delete_messages)

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise StandardError, 'test error' }
      }.to raise_error(StandardError, 'test error')
    end

    it 'supports complex lambda logic based on exception properties' do
      TestWorker.get_shoryuken_options['non_retryable_exceptions'] = lambda do |error|
        error.is_a?(ArgumentError) || (error.is_a?(StandardError) && error.message.include?('permanent'))
      end

      # ArgumentError should be deleted
      expect(sqs_queue).to receive(:delete_messages).with(entries: [
                                                           { id: '0', receipt_handle: sqs_msg.receipt_handle }
                                                         ])

      expect {
        subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { raise ArgumentError, 'invalid argument' }
      }.not_to raise_error

      # StandardError with 'permanent' should be deleted
      sqs_msg2 = build_message
      allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)

      expect(sqs_queue).to receive(:delete_messages).with(entries: [
                                                           { id: '0', receipt_handle: sqs_msg2.receipt_handle }
                                                         ])

      expect {
        subject.call(TestWorker.new, queue, sqs_msg2, sqs_msg2.body) { raise StandardError, 'permanent failure' }
      }.not_to raise_error

      # StandardError without 'permanent' should be retried
      sqs_msg3 = build_message
      allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)

      expect(sqs_queue).not_to receive(:delete_messages)

      expect {
        subject.call(TestWorker.new, queue, sqs_msg3, sqs_msg3.body) { raise StandardError, 'temporary failure' }
      }.to raise_error(StandardError, 'temporary failure')
    end
  end
end

