require 'spec_helper'

describe 'Shoryuken::Worker' do
  let(:sqs_queue) { double 'SQS Queue' }
  let(:queue)     { 'default' }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  describe '.perform_in' do
    it 'delays a message' do
      expect(sqs_queue).to receive(:send_message).with(
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        },
        message_body: 'message',
        delay_seconds: 60)

      TestWorker.perform_in(60, 'message')
    end

    it 'raises an exception' do
      expect {
        TestWorker.perform_in(901, 'message')
      }.to raise_error 'The maximum allowed delay is 15 minutes'
    end
  end

  describe '.perform_at' do
    it 'delays a message' do
      expect(sqs_queue).to receive(:send_message).with(
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        },
        message_body: 'message',
        delay_seconds: 60)

      TestWorker.perform_in(Time.now + 60, 'message')
    end

    it 'raises an exception' do
      expect {
        TestWorker.perform_in(Time.now + 901, 'message')
      }.to raise_error 'The maximum allowed delay is 15 minutes'
    end
  end

  describe '.perform_async' do
    it 'enqueues a message' do
      expect(sqs_queue).to receive(:send_message).with(
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        },
        message_body: 'message')

      TestWorker.perform_async('message')
    end

    it 'enqueues a message with options' do
      expect(sqs_queue).to receive(:send_message).with(
        delay_seconds: 60,
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        },
        message_body: 'delayed message')

      TestWorker.perform_async('delayed message', delay_seconds: 60)
    end

    # TODO: Deprecated
    it 'accepts an `queue` option' do
      new_queue = 'some_different_queue'

      expect(Shoryuken::Client).to receive(:queues).with(new_queue).and_return(sqs_queue)

      expect(sqs_queue).to receive(:send_message).with(
        message_attributes: {
          'shoryuken_class' => {
            string_value: TestWorker.to_s,
            data_type: 'String'
          }
        },
        message_body: 'delayed message')

      TestWorker.perform_async('delayed message', queue: new_queue)
    end
  end

  describe '.shoryuken_options' do
    let(:dummy_worker) { Class.new }

    before do
      dummy_worker.include Shoryuken::Worker
    end

    subject { dummy_worker.shoryuken_options shoryuken_options }

    context 'when using the queue key' do
      let(:shoryuken_options) { { 'queue' => 'a_queue' } }

      it 'warns about deprecation' do
        expect(Shoryuken.logger).to receive(:warn).
          with('[DEPRECATION] queue is deprecated as an option in favor of multiple queue support, please use queues instead').
          once
        subject
      end

      it 'does not keep the value from queue' do
        subject
        expect(dummy_worker.get_shoryuken_options['queue']).to be_nil
      end

      it 'merges the queue argument into the queues key' do
        subject
        expect(dummy_worker.get_shoryuken_options['queues']).to include('a_queue')
      end
    end

    context 'when passing queues with blocks' do
      let(:shoryuken_options) { {'queues' => ['a_queue', ->{ 'a_block_queue'}] } }

      it 'resolves the blocks and stores the queues at runtime' do
        subject
        expect(dummy_worker.get_shoryuken_options['queues']).to eql(['a_queue', 'a_block_queue', 'default'])
      end
    end

    context 'with changes to the default worker options' do
      let(:defaults) { { 'queues' => ['randomqueues'], 'auto_delete' => false } }
      let(:modified_options) { Shoryuken.default_worker_options.merge(defaults) }
      let(:shoryuken_options) { { 'auto_delete' => true } }

      before do
        allow(Shoryuken).to receive(:default_worker_options).
          and_return(modified_options)
      end

      it 'overrides default configuration' do
        expect{subject}.to change{dummy_worker.get_shoryuken_options['auto_delete']}.
          from(false).
          to(true)
      end

      it 'still contains configuration not explicitly changed' do
        subject
        expect(dummy_worker.get_shoryuken_options['queues']).to include('randomqueues')
      end
    end
  end

  describe '.server_middleware' do
    before do
      class FakeMiddleware
        def call(*args)
          yield
        end
      end
    end

    context 'no middleware is defined in the worker' do
      it 'returns the list of global middlewares' do
        expect(TestWorker.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::Timing)
        end

        expect(TestWorker.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::AutoDelete)
        end
      end
    end

    context 'the worker clears the middleware chain' do
      before do
        class NewTestWorker2
          include Shoryuken::Worker

          server_middleware do |chain|
            chain.clear
          end
        end
      end

      it 'returns an empty list' do
        expect(NewTestWorker2.server_middleware.entries).to be_empty
      end

      it 'does not affect the global middleware chain' do
        expect(Shoryuken.server_middleware.entries).not_to be_empty
      end
    end

    context 'the worker modifies the chain' do
      before do
        class NewTestWorker3
          include Shoryuken::Worker

          server_middleware do |chain|
            chain.remove Shoryuken::Middleware::Server::Timing
            chain.insert_before Shoryuken::Middleware::Server::AutoDelete, FakeMiddleware
          end
        end
      end

      it 'returns the combined global and worker middlewares' do
        expect(NewTestWorker3.server_middleware).not_to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::Timing)
        end

        expect(NewTestWorker3.server_middleware).to satisfy do |chain|
          chain.exists?(FakeMiddleware)
        end

        expect(NewTestWorker3.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::AutoDelete)
        end
      end

      it 'does not affect the global middleware chain' do
        expect(Shoryuken.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::Timing)
        end

        expect(Shoryuken.server_middleware).to satisfy do |chain|
          chain.exists?(Shoryuken::Middleware::Server::AutoDelete)
        end

        expect(Shoryuken.server_middleware).not_to satisfy do |chain|
          chain.exists?(FakeMiddleware)
        end
      end
    end
  end
end
