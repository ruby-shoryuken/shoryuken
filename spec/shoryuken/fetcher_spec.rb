require 'spec_helper'
require 'shoryuken/manager'
require 'shoryuken/fetcher'

# rubocop:disable Metrics/BlockLength
RSpec.describe Shoryuken::Fetcher do
  let(:queue)        { instance_double('Shoryuken::Queue', fifo?: false) }
  let(:queue_name)   { 'default' }
  let(:queue_config) { Shoryuken::Polling::QueueConfiguration.new(queue_name, {}) }
  let(:group)        { 'default' }

  let(:sqs_msg) do
    double(
      Shoryuken::Message,
      queue_url: queue_name,
      body: 'test',
      message_id: 'fc754df79cc24c4196ca5996a44b771e'
    )
  end

  subject { described_class.new(group) }

  describe '#fetch' do
    let(:limit) { 1 }

    specify do
      expect(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)

      Shoryuken.sqs_client_receive_message_opts[group] = { wait_time_seconds: 10 }

      expect(queue).to receive(:receive_messages).with(
        wait_time_seconds: 10,
        max_number_of_messages: limit,
        message_attribute_names: ['All'],
        attribute_names: ['All']
      ).and_return([])

      subject.fetch(queue_config, limit)
    end

    it 'logs debug only' do
      # See https://github.com/phstc/shoryuken/issues/435
      logger = double 'logger'

      allow(subject).to receive(:logger).and_return(logger)

      expect(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)

      expect(queue).to receive(:receive_messages).and_return([double('SQS Msg')])

      expect(logger).to receive(:debug).exactly(3).times
      expect(logger).to_not receive(:info)

      subject.fetch(queue_config, limit)
    end

    context 'when receive options per queue' do
      let(:limit) { 5 }

      specify do
        expect(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)

        Shoryuken.sqs_client_receive_message_opts[queue_name] = { max_number_of_messages: 1 }

        expect(queue).to receive(:receive_messages).with(
          max_number_of_messages: 1,
          message_attribute_names: ['All'],
          attribute_names: ['All']
        ).and_return([])

        subject.fetch(queue_config, limit)
      end
    end

    context 'when max_number_of_messages opt is great than limit' do
      it 'uses limit' do
        expect(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)

        Shoryuken.sqs_client_receive_message_opts[queue_name] = { max_number_of_messages: 20 }

        expect(queue).to receive(:receive_messages).with(
          max_number_of_messages: limit,
          message_attribute_names: ['All'],
          attribute_names: ['All']
        ).and_return([])

        subject.fetch(queue_config, limit)
      end
    end

    context 'when limit is greater than FETCH_LIMIT' do
      let(:limit) { 20 }

      specify do
        allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
        expect(queue).to receive(:receive_messages).with(
          max_number_of_messages: described_class::FETCH_LIMIT, attribute_names: ['All'], message_attribute_names: ['All']
        ).and_return([])

        subject.fetch(queue_config, limit)
      end
    end

    context 'when FIFO' do
      let(:limit) { 10 }
      let(:queue) { instance_double('Shoryuken::Queue', fifo?: true, name: queue_name) }

      it 'polls one message at a time' do
        # see https://github.com/phstc/shoryuken/pull/530

        allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
        expect(queue).to receive(:receive_messages).with(
          max_number_of_messages: 1, attribute_names: ['All'], message_attribute_names: ['All']
        ).and_return([])

        subject.fetch(queue_config, limit)
      end

      context 'with batch=true' do
        it 'polls the provided limit' do
          # see https://github.com/phstc/shoryuken/pull/530

          allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
          allow(Shoryuken.worker_registry).to receive(:batch_receive_messages?).with(queue.name).and_return(true)

          expect(queue).to receive(:receive_messages).with(
            max_number_of_messages: limit, attribute_names: ['All'], message_attribute_names: ['All']
          ).and_return([])

          subject.fetch(queue_config, limit)
        end
      end

      context 'with batch_options' do
        it 'perform multiple fetches until batch max size' do
          allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
          # Must be greater than batch timeout
          allow(queue).to receive(:visibility_timeout).and_return(70)
          allow(Shoryuken.worker_registry).to receive(:batch_receive_messages?).with(queue.name).and_return(true)
          allow(Shoryuken.worker_registry).to receive(:batch_options).with(queue.name).and_return(
            { 'max_size' => 20, 'timeout' => 60 }
          )

          # Read messages until we have a batch of 10 elements
          expect(queue).to receive(:receive_messages).with(
            max_number_of_messages: 10, attribute_names: ['All'], message_attribute_names: ['All']
          ).and_return(['sqs_msg'] * 10)
          expect(queue).to receive(:receive_messages).with(
            max_number_of_messages: 10, attribute_names: ['All'], message_attribute_names: ['All']
          ).and_return(['sqs_msg'] * 6)
          expect(queue).to receive(:receive_messages).with(
            max_number_of_messages: 4, attribute_names: ['All'], message_attribute_names: ['All']
          ).and_return(['sqs_msg'] * 4)

          subject.fetch(queue_config, 10)
        end

        it 'perform multiple fetches until batch timeout' do
          allow(Shoryuken::Client).to receive(:queues).with(queue_name).and_return(queue)
          # Must be greater than batch timeout
          allow(queue).to receive(:visibility_timeout).and_return(70)
          allow(Shoryuken.worker_registry).to receive(:batch_receive_messages?).with(queue.name).and_return(true)
          batch_timeout = 2
          allow(Shoryuken.worker_registry).to receive(:batch_options).with(queue.name).and_return(
            { 'max_size' => 20, 'timeout' => batch_timeout }
          )

          expect(queue).to receive(:receive_messages).with(
            max_number_of_messages: 10, attribute_names: ['All'], message_attribute_names: ['All']
          ) do
            # Let the batch timeout expires
            sleep batch_timeout + 1
            ['sqs_msg']
          end
          subject.fetch(queue_config, 10)
        end
      end
    end
  end
end
