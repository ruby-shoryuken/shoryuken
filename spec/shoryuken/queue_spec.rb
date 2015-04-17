require 'spec_helper'

describe Shoryuken::Queue do
  let(:credentials) { Aws::Credentials.new('access_key_id', 'secret_access_key') }
  let(:sqs)         { Aws::SQS::Client.new(stub_responses: true, credentials: credentials) }
  let(:queue_name)  { 'shoryuken' }
  let(:queue_url)   { 'https://eu-west-1.amazonaws.com:6059/123456789012/shoryuken' }

  subject { described_class.new(sqs, queue_name) }

  describe '#send_message' do
    it 'accepts SQS request parameters' do
      # https://docs.aws.amazon.com/sdkforruby/api/Aws/SQS/Client.html#send_message-instance_method
      expect(sqs).to receive(:send_message).with(hash_including(message_body: 'msg1'))

      subject.send_message(message_body: 'msg1')
    end

    it 'accepts a string' do
      expect(sqs).to receive(:send_message).with(hash_including(message_body: 'msg1'))

      subject.send_message('msg1')
    end

    context 'when body is invalid' do
      it 'raises ArgumentError for nil' do
        expect {
          subject.send_message(message_body: nil)
        }.to raise_error(ArgumentError, 'The message body must be a String and you passed a NilClass')
      end

      it 'raises ArgumentError for Fixnum' do
        expect {
          subject.send_message(message_body: 1)
        }.to raise_error(ArgumentError, 'The message body must be a String and you passed a Fixnum')
      end

      context 'when a client middleware' do
        class MyClientMiddleware
          def call(options)
            options[:message_body] = 'changed'

            yield
          end
        end

        before do
          Shoryuken.configure_client do |config|
            config.client_middleware do |chain|
              chain.add MyClientMiddleware
            end
          end
        end

        after do
          Shoryuken.configure_client do |config|
            config.client_middleware do |chain|
              chain.remove MyClientMiddleware
            end
          end
        end

        it 'invokes MyClientMiddleware' do
          expect(sqs).to receive(:send_message).with(hash_including(message_body: 'changed'))

          subject.send_message(message_body: 'original')
        end
      end
    end
  end

  describe '#send_messages' do
    it 'accepts SQS request parameters' do
      # https://docs.aws.amazon.com/sdkforruby/api/Aws/SQS/Client.html#send_message_batch-instance_method
      expect(sqs).to receive(:send_message_batch).with(hash_including(entries: [{ id: '0', message_body: 'msg1'}, { id: '1', message_body: 'msg2' }]))

      subject.send_messages(entries: [{ id: '0', message_body: 'msg1'}, { id: '1', message_body: 'msg2' }])
    end

    it 'accepts an array of string' do
      expect(sqs).to receive(:send_message_batch).with(hash_including(entries: [{ id: '0', message_body: 'msg1'}, { id: '1', message_body: 'msg2' }]))

      subject.send_messages(%w(msg1 msg2))
    end

    context 'when body is invalid' do
      it 'raises ArgumentError for nil' do
        expect {
          subject.send_messages(entries: [message_body: nil])
        }.to raise_error(ArgumentError, 'The message body must be a String and you passed a NilClass')
      end

      it 'raises ArgumentError for Fixnum' do
        expect {
          subject.send_messages(entries: [message_body: 1])
        }.to raise_error(ArgumentError, 'The message body must be a String and you passed a Fixnum')
      end
    end
  end
end
