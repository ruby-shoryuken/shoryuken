require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/fetcher'

describe Shoryuken::Fetcher do
  let(:queue)      { instance_double('Shoryuken::Queue', receive_messages: []) }
  let(:queue_name) { 'default' }
  let(:queue_config) { Shoryuken::Polling::QueueConfiguration.new(queue_name, {}) }

  let(:sqs_msg) do
    double(Shoryuken::Message,
      queue_url: queue_name,
      body: 'test',
      message_id: 'fc754df79cc24c4196ca5996a44b771e',
          )
  end

  subject { described_class.new }

  describe '#fetch' do
    before do
      allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
    end

    it 'calls Shoryuken::Client to receive messages' do
      expect(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
      expect(queue).to receive(:receive_messages).
        with(max_number_of_messages: 1, attribute_names: ['All'], message_attribute_names: ['All'])
      subject.fetch(queue_config, 1)
    end

    it 'maxes messages to receive to 10 (SQS limit)' do
      expect(queue).to receive(:receive_messages).
        with(max_number_of_messages: 10, attribute_names: ['All'], message_attribute_names: ['All'])
      subject.fetch(queue_config, 20)
    end

    context 'when an error is raised' do
      let(:exception) { StandardError.new('Error fetching messages') }

      before do
        allow(queue).to receive(:receive_messages).and_raise(exception)
      end

      it 'does not raise the error' do
        expect do
          subject.fetch(queue_config, 1)
        end.not_to raise_error
      end

      it 'returns an empty set of messages' do
        return_value = subject.fetch(queue_config, 1)
        expect(return_value).to eq([])
      end

      context 'when configured to raise errors' do
        around(:each) do |example|
          original_opts = Shoryuken.sqs_client_receive_message_opts
          Shoryuken.sqs_client_receive_message_opts = original_opts.dup.merge(raise_errors: true)

          example.run

          Shoryuken.sqs_client_receive_message_opts = original_opts
        end

        it 'raises the error' do
          expect do
            subject.fetch(queue_config, 1)
          end.to raise_error(StandardError, 'Error fetching messages')
        end
      end
    end
  end
end
