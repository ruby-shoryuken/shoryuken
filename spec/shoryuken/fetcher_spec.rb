require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/fetcher'

describe Shoryuken::Fetcher do
  let(:queue)      { instance_double('Shoryuken::Queue') }
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
    it 'calls Shoryuken::Client to receive messages' do
      expect(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
      expect(queue).to receive(:receive_messages).
        with(max_number_of_messages: 1, attribute_names: ['All'], message_attribute_names: ['All']).
        and_return([])
      subject.fetch(queue_config, 1)
    end

    it 'maxes messages to receive to 10 (SQS limit)' do
      allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
      expect(queue).to receive(:receive_messages).
        with(max_number_of_messages: 10, attribute_names: ['All'], message_attribute_names: ['All']).
        and_return([])
      subject.fetch(queue_config, 20)
    end
  end
end
