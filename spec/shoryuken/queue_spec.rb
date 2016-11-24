require 'spec_helper'

describe Shoryuken::Queue do
  let(:credentials) { Aws::Credentials.new('access_key_id', 'secret_access_key') }
  let(:sqs) { Aws::SQS::Client.new(stub_responses: true, credentials: credentials) }
  let(:queue_name) { 'shoryuken' }
  let(:queue_url) { 'https://eu-west-1.amazonaws.com:6059/123456789012/shoryuken' }
  let(:attribute_response) { double 'Aws::SQS::Types::GetQueueAttributesResponse' }

  subject { described_class.new(sqs, queue_name) }
  before {
    # Required as Aws::SQS::Client.get_queue_url returns 'String' when responses are stubbed,
    # which is not accepted by Aws::SQS::Client.get_queue_attributes for :queue_name parameter.
    allow(subject).to receive(:url).and_return(queue_url)
  }

  describe '#send_message' do
    before {
      allow(subject).to receive(:is_fifo?).and_return(false)
    }
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
          allow(Shoryuken).to receive(:server?).and_return(false)
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
    before {
      allow(subject).to receive(:is_fifo?).and_return(false)
    }
    it 'accepts SQS request parameters' do
      # https://docs.aws.amazon.com/sdkforruby/api/Aws/SQS/Client.html#send_message_batch-instance_method
      expect(sqs).to receive(:send_message_batch).with(hash_including(entries: [{id: '0', message_body: 'msg1'}, {id: '1', message_body: 'msg2'}]))

      subject.send_messages(entries: [{id: '0', message_body: 'msg1'}, {id: '1', message_body: 'msg2'}])
    end

    it 'accepts an array of messages' do
      expect(sqs).to receive(:send_message_batch).with(hash_including(entries: [{id: '0', message_body: 'msg1', delay_seconds: 1, message_attributes: {attr: 'attr1'}}, {id: '1', message_body: 'msg2', delay_seconds: 1, message_attributes: {attr: 'attr2'}}]))

      subject.send_messages([
                                {
                                    message_body:       'msg1',
                                    delay_seconds:      1,
                                    message_attributes: {attr: 'attr1'}
                                }, {
                                    message_body:       'msg2',
                                    delay_seconds:      1,
                                    message_attributes: {attr: 'attr2'}
                                }
                            ])
    end

    context 'when FIFO is configured without content deduplication' do
      before {
        # Arrange
        allow(subject).to receive(:is_fifo?).and_return(true)
        # Pre-Assert
        expect(sqs).to receive(:send_message_batch) do |arg|
          expect(arg).to include(:entries)
          first_entry = arg[:entries].first
          expect(first_entry).to include({id: '0', message_body: 'msg1', message_group_id: 'ShoryukenMessage'})
          expect(first_entry[:message_deduplication_id]).to be_a String
        end
      }
      it 'sends with message_group_id and message_deduplication_id when an array is sent' do
        subject.send_messages([{message_body: 'msg1', message_attributes: {attr: 'attr1'}}])
      end
      it 'sends with message_group_id and message_deduplication_id  when a hash is sent' do
        subject.send_messages(entries: [{id: '0', message_body: 'msg1'}])
      end
    end

    context 'when FIFO is configured with content deduplication' do
      before {
        # Arrange
        allow(subject).to receive(:is_fifo?).and_return(true)
        allow(subject).to receive(:has_content_deduplication?).and_return(true)
        # Pre-Assert
        expect(sqs).to receive(:send_message_batch) do |arg|
          expect(arg).to include(:entries)
          first_entry = arg[:entries].first
          expect(first_entry).to match({id: '0', message_body: 'msg1', message_group_id: 'ShoryukenMessage', message_attributes: {attr: 'attr1'}})
        end
      }
      it 'sends with message_group_id when argument is an array' do
        subject.send_messages([{message_body: 'msg1', message_attributes: {attr: 'attr1'}}])
      end
      it 'sends with message_group_id when a hash is sent' do
        subject.send_messages(entries: [{id: '0', message_body: 'msg1', message_attributes: {attr: 'attr1'}}])
      end
    end


    it 'accepts an array of string' do
      expect(sqs).to receive(:send_message_batch).with(hash_including(entries: [{id: '0', message_body: 'msg1'}, {id: '1', message_body: 'msg2'}]))

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

  describe '#is_fifo?' do
    before {
      # Required as Aws::SQS::Client.get_queue_url returns 'String' when responses are stubbed.
      allow(subject).to receive(:url).and_return(queue_url)
      allow(sqs).to receive(:get_queue_attributes).with({queue_url: queue_url, attribute_names: ['FifoQueue', 'ContentBasedDeduplication']}).and_return(attribute_response)

    }
    context 'when queue is FIFO' do
      before {
        allow(attribute_response).to receive(:attributes).and_return({'FifoQueue' => 'true', 'ContentBasedDeduplication' => 'true'})
      }
      it 'Returns True' do
        expect(subject.is_fifo?).to eq true
      end
    end
    context 'when queue is not FIFO' do
      before {
        allow(attribute_response).to receive(:attributes).and_return({'FifoQueue' => 'false', 'ContentBasedDeduplication' => 'false'})
      }
      it 'Returns False' do
        expect(subject.is_fifo?).to eq false
      end
    end
  end

  describe '#has_content_deduplication?' do
    before {
      allow(sqs).to receive(:get_queue_attributes).with({queue_url: queue_url, attribute_names: ['FifoQueue', 'ContentBasedDeduplication']}).and_return(attribute_response)

    }
    context 'when queue has content deduplicaiton' do
      before {
        allow(attribute_response).to receive(:attributes).and_return({'FifoQueue' => 'true', 'ContentBasedDeduplication' => 'true'})
      }
      it 'Returns True' do
        expect(subject.has_content_deduplication?).to eq true
      end
    end
    context 'when queue does not have content deduplication' do
      before {
        allow(attribute_response).to receive(:attributes).and_return({'FifoQueue' => 'true', 'ContentBasedDeduplication' => 'false'})
      }
      it 'Returns False' do
        expect(subject.has_content_deduplication?).to eq false
      end
    end
  end
end
