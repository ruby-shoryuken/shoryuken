require 'spec_helper'

describe Shoryuken::Queue do
  let(:credentials) { Aws::Credentials.new('access_key_id', 'secret_access_key') }
  let(:sqs) { Aws::SQS::Client.new(stub_responses: true, credentials: credentials) }
  let(:queue_name) { 'shoryuken' }
  let(:queue_url) { 'https://eu-west-1.amazonaws.com:6059/123456789012/shoryuken' }

  subject { described_class.new(sqs, queue_name) }
  before {
    # Required as Aws::SQS::Client.get_queue_url returns 'String' when responses are stubbed,
    # which is not accepted by Aws::SQS::Client.get_queue_attributes for :queue_name parameter.
    allow(subject).to receive(:url).and_return(queue_url)
  }

  describe '#send_message' do
    before {
      allow(subject).to receive(:fifo?).and_return(false)
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

  describe '#send_messages' do
    before {
      allow(subject).to receive(:fifo?).and_return(false)
    }
    it 'accepts SQS request parameters' do
      # https://docs.aws.amazon.com/sdkforruby/api/Aws/SQS/Client.html#send_message_batch-instance_method
      expect(sqs).to receive(:send_message_batch).with(hash_including(entries: [{id: '0', message_body: 'msg1'}, {id: '1', message_body: 'msg2'}]))

      subject.send_messages(entries: [{id: '0', message_body: 'msg1'}, {id: '1', message_body: 'msg2'}])
    end

    it 'accepts an array of messages' do
      options = { entries: [{ id: '0',
                              message_body: 'msg1',
                              delay_seconds: 1,
                              message_attributes: { attr: 'attr1' } },
                            { id: '1',
                              message_body: 'msg2',
                              delay_seconds: 1,
                              message_attributes: { attr: 'attr2' } }] }

      expect(sqs).to receive(:send_message_batch).with(hash_including(options))

      subject.send_messages([{ message_body:       'msg1',
                               delay_seconds:      1,
                               message_attributes: { attr: 'attr1' }
                             }, {
                               message_body:       'msg2',
                               delay_seconds:      1,
                               message_attributes: { attr: 'attr2' }
                             }])
    end

    context 'when FIFO' do
      before do
        allow(subject).to receive(:fifo?).and_return(true)
      end

      context 'and message_group_id and message_deduplication_id are absent' do
        it 'sets default values' do
          expect(sqs).to receive(:send_message_batch) do |arg|
            first_entry = arg[:entries].first

            expect(first_entry[:message_group_id]).to eq described_class::MESSAGE_GROUP_ID
            expect(first_entry[:message_deduplication_id]).to be
          end

          subject.send_messages([{ message_body: 'msg1', message_attributes: { attr: 'attr1' } }])
        end
      end

      context 'and message_group_id and message_deduplication_id are present' do
        it 'preserves existing values' do
          expect(sqs).to receive(:send_message_batch) do |arg|
            first_entry = arg[:entries].first

            expect(first_entry[:message_group_id]).to eq 'my group'
            expect(first_entry[:message_deduplication_id]).to eq 'my id'
          end

          subject.send_messages([{ message_body: 'msg1',
                                   message_attributes: { attr: 'attr1' },
                                   message_group_id: 'my group',
                                   message_deduplication_id: 'my id' }])
        end
      end
    end

    it 'accepts an array of string' do
      expect(sqs).to receive(:send_message_batch).with(hash_including(entries: [{ id: '0', message_body: 'msg1' }, { id: '1', message_body: 'msg2' }]))

      subject.send_messages(%w(msg1 msg2))
    end
  end

  describe '#fifo?' do
    before do
      attribute_response = double 'Aws::SQS::Types::GetQueueAttributesResponse'

      allow(attribute_response).to receive(:attributes).and_return('FifoQueue' => fifo.to_s, 'ContentBasedDeduplication' => 'true')
      allow(subject).to receive(:url).and_return(queue_url)
      allow(sqs).to receive(:get_queue_attributes).with(queue_url: queue_url, attribute_names: ['All']).and_return(attribute_response)
    end

    context 'when queue is FIFO' do
      let(:fifo) { true }

      it { expect(subject.fifo?).to be }
    end

    context 'when queue is not FIFO' do
      let(:fifo) { false }

      it { expect(subject.fifo?).to_not be }
    end
  end
end
