# frozen_string_literal: true

RSpec.describe Shoryuken::Worker::DefaultExecutor do
  let(:sqs_queue) { double 'SQS Queue', name: queue, fifo?: false }
  let(:queue)     { 'default' }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  describe '.perform_in' do
    it 'delays a message' do
      expect(sqs_queue).to receive(:send_message).with(
        {
          message_attributes: {
            'shoryuken_class' => {
              string_value: TestWorker.to_s,
              data_type: 'String'
            }
          },
          message_body: 'message',
          delay_seconds: 60
        }
      )

      TestWorker.perform_in(60, 'message')
    end

    it 'raises an exception' do
      expect {
        TestWorker.perform_in(901, 'message')
      }.to raise_error 'The maximum allowed delay is 15 minutes'
    end

    it 'sends a negative interval with a delay of 0' do
      expect(sqs_queue).to receive(:send_message).with(hash_including(delay_seconds: 0))

      TestWorker.perform_in(-5, 'message')
    end

    context 'with a FIFO queue' do
      let(:sqs_queue) { double 'SQS Queue', name: queue, fifo?: true }

      it 'raises before the send when a delay is given' do
        expect(sqs_queue).not_to receive(:send_message)

        expect {
          TestWorker.perform_in(5, 'message')
        }.to raise_error(
          Shoryuken::Errors::FifoDelayNotSupportedError,
          "FIFO queue 'default' does not support per-message delays"
        )
      end

      it 'checks the queue given in the options' do
        other_queue = double 'Other SQS Queue', name: 'other.fifo', fifo?: true
        allow(Shoryuken::Client).to receive(:queues).with('other.fifo').and_return(other_queue)

        expect {
          TestWorker.perform_in(5, 'message', queue: 'other.fifo')
        }.to raise_error(Shoryuken::Errors::FifoDelayNotSupportedError, /other\.fifo/)
      end

      it 'sends an interval of 0' do
        expect(sqs_queue).to receive(:send_message).with(hash_including(delay_seconds: 0))

        TestWorker.perform_in(0, 'message')
      end

      it 'sends a negative interval with a delay of 0' do
        expect(sqs_queue).to receive(:send_message).with(hash_including(delay_seconds: 0))

        TestWorker.perform_in(-5, 'message')
      end
    end

    context 'with several worker queues' do
      before { TestWorker.get_shoryuken_options['queue'] = %w[queue1 queue2] }

      it 'raises without a queue option' do
        expect(Shoryuken::Client).not_to receive(:queues)

        expect {
          TestWorker.perform_in(60, 'message')
        }.to raise_error(ArgumentError, /TestWorker has several queues \(queue1, queue2\)/)
      end

      it 'raises without a queue option when no delay is given' do
        expect(Shoryuken::Client).not_to receive(:queues)

        expect { TestWorker.perform_in(0, 'message') }.to raise_error(ArgumentError, /pass the queue: option/)
      end

      it 'sends to the queue given in the options' do
        expect(Shoryuken::Client).to receive(:queues).with('queue2').twice.and_return(sqs_queue)
        expect(sqs_queue).to receive(:send_message).with(hash_including(delay_seconds: 60))

        TestWorker.perform_in(60, 'message', queue: 'queue2')
      end
    end
  end

  describe '.perform_at' do
    it 'delays a message' do
      expect(sqs_queue).to receive(:send_message).with(
        {
          message_attributes: {
            'shoryuken_class' => {
              string_value: TestWorker.to_s,
              data_type: 'String'
            }
          },
          message_body: 'message',
          delay_seconds: 60
        }
      )

      TestWorker.perform_in(Time.now + 60, 'message')
    end

    it 'raises an exception' do
      expect {
        TestWorker.perform_in(Time.now + 901, 'message')
      }.to raise_error 'The maximum allowed delay is 15 minutes'
    end

    it 'sends a time in the past with a delay of 0' do
      expect(sqs_queue).to receive(:send_message).with(hash_including(delay_seconds: 0))

      TestWorker.perform_at(Time.now - 60, 'message')
    end

    context 'with a FIFO queue' do
      let(:sqs_queue) { double 'SQS Queue', name: queue, fifo?: true }

      it 'raises before the send for a future time' do
        expect(sqs_queue).not_to receive(:send_message)

        expect {
          TestWorker.perform_at(Time.now + 60, 'message')
        }.to raise_error(Shoryuken::Errors::FifoDelayNotSupportedError)
      end

      it 'sends a time in the past with a delay of 0' do
        expect(sqs_queue).to receive(:send_message).with(hash_including(delay_seconds: 0))

        TestWorker.perform_at(Time.now - 60, 'message')
      end
    end
  end

  describe '.perform_async' do
    it 'enqueues a message' do
      expect(sqs_queue).to receive(:send_message).with(
        {
          message_attributes: {
            'shoryuken_class' => {
              string_value: TestWorker.to_s,
              data_type: 'String'
            }
          },
          message_body: 'message'
        }
      )

      TestWorker.perform_async('message')
    end

    it 'enqueues a message with options' do
      expect(sqs_queue).to receive(:send_message).with(
        {
          delay_seconds: 60,
          message_attributes: {
            'shoryuken_class' => {
              string_value: TestWorker.to_s,
              data_type: 'String'
            }
          },
          message_body: 'delayed message'
        }
      )

      TestWorker.perform_async('delayed message', delay_seconds: 60)
    end

    it 'accepts an `queue` option' do
      new_queue = 'some_different_queue'

      expect(Shoryuken::Client).to receive(:queues).with(new_queue).and_return(sqs_queue)

      expect(sqs_queue).to receive(:send_message).with(
        {
          message_attributes: {
            'shoryuken_class' => {
              string_value: TestWorker.to_s,
              data_type: 'String'
            }
          },
          message_body: 'delayed message'
        }
      )

      TestWorker.perform_async('delayed message', queue: new_queue)
    end

    context 'with several worker queues' do
      before { TestWorker.get_shoryuken_options['queue'] = %w[queue1 queue2] }

      it 'raises without a queue option' do
        expect(Shoryuken::Client).not_to receive(:queues)

        expect {
          TestWorker.perform_async('message')
        }.to raise_error(
          ArgumentError,
          'TestWorker has several queues (queue1, queue2): pass the queue: option to choose one'
        )
      end

      it 'sends to the queue given in the options' do
        expect(Shoryuken::Client).to receive(:queues).with('queue2').and_return(sqs_queue)
        expect(sqs_queue).to receive(:send_message).with(hash_including(message_body: 'message'))

        TestWorker.perform_async('message', queue: 'queue2')
      end
    end

    context 'with a one-element worker queue array' do
      before { TestWorker.get_shoryuken_options['queue'] = [queue] }

      it 'sends to that queue' do
        expect(sqs_queue).to receive(:send_message).with(hash_including(message_body: 'message'))

        TestWorker.perform_async('message')
      end
    end

    it 'does not mutate the caller-supplied options hash' do
      allow(sqs_queue).to receive(:send_message)

      options = { queue: queue, message_attributes: { 'custom' => { string_value: 'v', data_type: 'String' } } }

      TestWorker.perform_async('message', options)

      # :queue must not be deleted, :message_body must not be injected, and the
      # nested message_attributes must not gain shoryuken_class - otherwise a
      # reused options hash would reroute/corrupt later enqueues.
      expect(options).to eq(queue: queue, message_attributes: { 'custom' => { string_value: 'v', data_type: 'String' } })
    end
  end
end
