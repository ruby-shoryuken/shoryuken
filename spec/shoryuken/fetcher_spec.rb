require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/fetcher'


describe Shoryuken::Fetcher do
  let(:manager)    { double Shoryuken::Manager }
  let(:queue)      { double Shoryuken::Queue }
  let(:queue_name) { 'default' }
  let(:queues) { [queue_name] }
  let(:queue_config) { Shoryuken::Polling::QueueConfiguration.new(queue_name, {}) }
  let(:polling_strategy) { Shoryuken::Polling::WeightedRoundRobin.new(queues)  }

  let(:sqs_msg) do
    double Shoryuken::Message,
      queue_url: queue_name,
      body: 'test',
      message_id: 'fc754df79cc24c4196ca5996a44b771e'
  end

  subject { described_class.new(manager, polling_strategy) }

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
  end

  describe '#fetch' do
    it 'calls pause when no message' do
      allow(queue).to receive(:receive_messages)
        .with(max_number_of_messages: 1, attribute_names: ['All'], message_attribute_names: ['All'])
        .and_return([])

      expect(polling_strategy).to receive(:messages_found).with(queue_config, 0)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_config, 1)
    end

    it 'assigns messages' do
      allow(queue).to receive(:receive_messages)
        .with(max_number_of_messages: 5, attribute_names: ['All'], message_attribute_names: ['All'])
        .and_return(sqs_msg)

      expect(polling_strategy).to receive(:messages_found).with(queue_config, 1)
      expect(manager).to receive(:assign).with(queue_name, sqs_msg)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_config, 5)
    end

    it 'assigns messages in batch' do
      TestWorker.get_shoryuken_options['batch'] = true

      allow(queue).to receive(:receive_messages)
        .with(max_number_of_messages: described_class::FETCH_LIMIT, attribute_names: ['All'], message_attribute_names: ['All'])
        .and_return(sqs_msg)

      expect(polling_strategy).to receive(:messages_found).with(queue_config, 1)
      expect(manager).to receive(:assign).with(queue_name, [sqs_msg])
      expect(manager).to receive(:dispatch)

      subject.fetch(queue_config, 5)
    end

    context 'when worker not found' do
      let(:queue_name) { 'notfound' }

      it 'ignores batch' do
        allow(queue).to receive(:receive_messages)
          .with(max_number_of_messages: 5, attribute_names: ['All'], message_attribute_names: ['All'])
          .and_return(sqs_msg)

        expect(polling_strategy).to receive(:messages_found).with(queue_config, 1)
        expect(manager).to receive(:assign).with(queue_name, sqs_msg)
        expect(manager).to receive(:dispatch)

        subject.fetch(queue_config, 5)
      end
    end
  end
end
