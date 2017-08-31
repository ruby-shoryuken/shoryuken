require 'spec_helper'

RSpec.describe 'Shoryuken::Worker' do
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
    it 'registers a worker' do
      expect(Shoryuken.worker_registry.workers('default')).to eq([TestWorker])
    end

    it 'accepts a block as a queue' do
      $queue_prefix = 'production'

      class NewTestWorker
        include Shoryuken::Worker

        shoryuken_options queue: ->{ "#{$queue_prefix}_default" }
      end

      expect(Shoryuken.worker_registry.workers('production_default')).to eq([NewTestWorker])
      expect(NewTestWorker.get_shoryuken_options['queue']).to eq 'production_default'
    end

    it 'does not change the original hash' do
      class TestWorker
        include Shoryuken::Worker

        OPT = { queue: :default }

        shoryuken_options OPT
      end

      expect(TestWorker::OPT['queue']).to eq(nil)
      expect(TestWorker.get_shoryuken_options['queue']).to eq('default')
      expect(TestWorker::OPT[:queue]).to eq(:default)
    end

    it 'accepts an array as a queue' do
      class WorkerMultipleQueues
        include Shoryuken::Worker

        shoryuken_options queue: %w[queue1 queue2 queue3]
      end

      expect(Shoryuken.worker_registry.workers('queue1')).to eq([WorkerMultipleQueues])
      expect(Shoryuken.worker_registry.workers('queue2')).to eq([WorkerMultipleQueues])
      expect(Shoryuken.worker_registry.workers('queue3')).to eq([WorkerMultipleQueues])
    end

    it 'is possible to configure the global defaults' do
      queue = SecureRandom.uuid
      Shoryuken.default_worker_options['queue'] = queue

      class GlobalDefaultsTestWorker
        include Shoryuken::Worker

        shoryuken_options auto_delete: true
      end

      expect(GlobalDefaultsTestWorker.get_shoryuken_options['queue']).to eq queue
      expect(GlobalDefaultsTestWorker.get_shoryuken_options['auto_delete']).to eq true
      expect(GlobalDefaultsTestWorker.get_shoryuken_options['batch']).to eq false
    end

    it 'accepts a symbol as a queue and converts to string' do
      class SymbolQueueTestWorker
        include Shoryuken::Worker

        shoryuken_options queue: :default
      end

      expect(SymbolQueueTestWorker.get_shoryuken_options['queue']).to eq 'default'
    end

    it 'accepts an array that contains symbols as a queue and converts to string' do
      class WorkerMultipleSymbolQueues
        include Shoryuken::Worker

        shoryuken_options queue: %i[symbol_queue1 symbol_queue2 symbol_queue3]
      end

      expect(Shoryuken.worker_registry.workers('symbol_queue1')).to eq([WorkerMultipleSymbolQueues])
      expect(Shoryuken.worker_registry.workers('symbol_queue2')).to eq([WorkerMultipleSymbolQueues])
      expect(Shoryuken.worker_registry.workers('symbol_queue3')).to eq([WorkerMultipleSymbolQueues])
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
