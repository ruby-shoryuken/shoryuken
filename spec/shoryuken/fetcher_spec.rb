require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/fetcher'

describe Shoryuken::Fetcher do
  let(:manager)    { double Shoryuken::Manager }
  let(:queue)      { double Shoryuken::Queue }
  let(:queue_name) { 'default' }
  let(:queue_config) { Shoryuken::Polling::QueueConfiguration.new(queue_name, {}) }

  let(:sqs_msg) do
    double Shoryuken::Message,
      queue_url: queue_name,
      body: 'test',
      message_id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e'
  end

  subject { described_class.new(manager) }

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
  end


  describe '#fetch' do
    it 'calls pause when no message' do
      allow(queue).to receive(:receive_messages).with(max_number_of_messages: 1, attribute_names: ['All'], message_attribute_names: ['All']).and_return([])

      expect(manager).to receive(:queue_empty).with(queue_config)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_config, 1)
    end

    it 'assigns messages' do
      allow(queue).to receive(:receive_messages).with(max_number_of_messages: 5, attribute_names: ['All'], message_attribute_names: ['All']).and_return(sqs_msg)

      expect(manager).to receive(:messages_present).with(queue_config)
      expect(manager).to receive(:assign).with(queue_name, sqs_msg)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_config, 5)
    end

    it 'assigns messages in batch' do
      TestWorker.get_shoryuken_options['batch'] = true

      allow(queue).to receive(:receive_messages).with(max_number_of_messages: described_class::FETCH_LIMIT, attribute_names: ['All'], message_attribute_names: ['All']).and_return(sqs_msg)

      expect(manager).to receive(:messages_present).with(queue_config)
      expect(manager).to receive(:assign).with(queue_name, [sqs_msg])
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_config, 5)
    end

    context 'when worker not found' do
      let(:queue_name) { 'notfound' }

      it 'ignores batch' do
        allow(queue).to receive(:receive_messages).with(max_number_of_messages: 5, attribute_names: ['All'], message_attribute_names: ['All']).and_return(sqs_msg)

        expect(manager).to receive(:messages_present).with(queue_config)
        expect(manager).to receive(:assign).with(queue_name, sqs_msg)
        expect(manager).to receive(:dispatch)

        subject.fetch(queue_config, 5)
      end
    end
  end
end
