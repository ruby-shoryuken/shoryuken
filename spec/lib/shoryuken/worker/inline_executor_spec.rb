# frozen_string_literal: true

RSpec.describe Shoryuken::Worker::InlineExecutor do
  before do
    Shoryuken.worker_executor = described_class
  end

  describe '.perform_async' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform).with(anything, 'test')

      TestWorker.perform_async('test')
    end

    it 'properly sets message_attributes' do
      custom_attributes = {
        'custom_key' => { string_value: 'custom_value', data_type: 'String' }
      }

      expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msg, _|
        expect(sqs_msg.message_attributes).to include('shoryuken_class')
        expect(sqs_msg.message_attributes).to include('custom_key')
        expect(sqs_msg.message_attributes['custom_key'][:string_value]).to eq('custom_value')
      end

      TestWorker.perform_async('test', message_attributes: custom_attributes)
    end

    it 'does not mutate the caller-supplied options hash' do
      allow_any_instance_of(TestWorker).to receive(:perform)

      options = { queue: 'a_queue', message_attributes: { 'custom' => { string_value: 'v', data_type: 'String' } } }

      TestWorker.perform_async('test', options)

      # :queue and :message_attributes must survive intact so a reused options
      # hash routes later jobs correctly instead of falling back to the default.
      expect(options).to eq(queue: 'a_queue', message_attributes: { 'custom' => { string_value: 'v', data_type: 'String' } })
    end

    context 'with several worker queues' do
      before { TestWorker.get_shoryuken_options['queue'] = %w[queue1 queue2] }

      it 'raises without a queue option' do
        expect_any_instance_of(TestWorker).not_to receive(:perform)

        expect {
          TestWorker.perform_async('test')
        }.to raise_error(
          ArgumentError,
          'TestWorker has several queues (queue1, queue2): pass the queue: option to choose one'
        )
      end

      it 'runs the job with the queue given in the options' do
        expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msg, body|
          expect(sqs_msg.queue_name).to eq('queue2')
          expect(body).to eq('test')
        end

        TestWorker.perform_async('test', queue: 'queue2')
      end
    end

    context 'with an empty worker queue array' do
      before { TestWorker.get_shoryuken_options['queue'] = [] }

      it 'raises without a queue option' do
        expect {
          TestWorker.perform_async('test')
        }.to raise_error(ArgumentError, 'TestWorker has no queue: pass the queue: option')
      end
    end

    context 'with a one-element worker queue array' do
      before { TestWorker.get_shoryuken_options['queue'] = %w[queue1] }

      it 'runs the job with that queue' do
        expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msg, _|
          expect(sqs_msg.queue_name).to eq('queue1')
        end

        TestWorker.perform_async('test')
      end
    end

    it 'runs the job with the queue of a single-queue worker' do
      expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msg, _|
        expect(sqs_msg.queue_name).to eq('default')
      end

      TestWorker.perform_async('test')
    end

    context 'when the worker has no shoryuken_options' do
      let(:worker_class) do
        stub_const(
          'NoOptionsWorker',
          Class.new do
            include Shoryuken::Worker

            def perform(sqs_msg, body); end
          end
        )
      end

      it 'uses the default worker options' do
        expect_any_instance_of(worker_class).to receive(:perform).with(kind_of(Shoryuken::InlineMessage), 'test')

        worker_class.perform_async('test')
      end

      it 'passes a batch when the default worker options enable batch' do
        allow(Shoryuken).to receive(:default_worker_options).and_return('queue' => 'default', 'batch' => true)

        expect_any_instance_of(worker_class).to receive(:perform).with([kind_of(Shoryuken::InlineMessage)], ['test'])

        worker_class.perform_async('test')
      end
    end
  end

  describe '.perform_in' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform).with(anything, 'test')

      TestWorker.perform_in(60, 'test')
    end

    it 'raises without a queue option for a worker with several queues' do
      TestWorker.get_shoryuken_options['queue'] = %w[queue1 queue2]

      expect {
        TestWorker.perform_in(60, 'test')
      }.to raise_error(ArgumentError, /TestWorker has several queues \(queue1, queue2\)/)
    end

    it 'properly passes message_attributes to perform_async' do
      custom_attributes = {
        'custom_key' => { string_value: 'custom_value', data_type: 'String' }
      }

      expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msg, _|
        expect(sqs_msg.message_attributes).to include('shoryuken_class')
        expect(sqs_msg.message_attributes).to include('custom_key')
        expect(sqs_msg.message_attributes['custom_key'][:string_value]).to eq('custom_value')
      end

      TestWorker.perform_in(60, 'test', message_attributes: custom_attributes)
    end
  end

  context 'batch' do
    before do
      TestWorker.get_shoryuken_options['batch'] = true
    end

    after do
      TestWorker.get_shoryuken_options['batch'] = false
    end

    describe '.perform_async' do
      specify do
        expect_any_instance_of(TestWorker).to receive(:perform).with(anything, ['test'])

        TestWorker.perform_async('test')
      end

      it 'properly passes message_attributes with batch' do
        custom_attributes = {
          'custom_key' => { string_value: 'custom_value', data_type: 'String' }
        }

        expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msgs, _|
          expect(sqs_msgs.first.message_attributes).to include('shoryuken_class')
          expect(sqs_msgs.first.message_attributes).to include('custom_key')
          expect(sqs_msgs.first.message_attributes['custom_key'][:string_value]).to eq('custom_value')
        end

        TestWorker.perform_async('test', message_attributes: custom_attributes)
      end
    end

    describe '.perform_in' do
      specify do
        expect_any_instance_of(TestWorker).to receive(:perform).with(anything, ['test'])

        TestWorker.perform_in(60, 'test')
      end

      it 'properly passes message_attributes with batch' do
        custom_attributes = {
          'custom_key' => { string_value: 'custom_value', data_type: 'String' }
        }

        expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msgs, _|
          expect(sqs_msgs.first.message_attributes).to include('shoryuken_class')
          expect(sqs_msgs.first.message_attributes).to include('custom_key')
          expect(sqs_msgs.first.message_attributes['custom_key'][:string_value]).to eq('custom_value')
        end

        TestWorker.perform_in(60, 'test', message_attributes: custom_attributes)
      end
    end
  end
end
