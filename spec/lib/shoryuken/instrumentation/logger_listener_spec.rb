# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Instrumentation::LoggerListener do
  let(:logger) { instance_double(Logger, info: nil, error: nil, debug: nil, warn: nil) }
  let(:listener) { described_class.new(logger) }

  describe '#initialize' do
    it 'accepts a custom logger' do
      expect(listener.logger).to eq(logger)
    end

    it 'defaults to Shoryuken.logger' do
      listener_without_logger = described_class.new
      expect(listener_without_logger.logger).to eq(Shoryuken.logger)
    end
  end

  describe '#call' do
    context 'with app.started event' do
      it 'logs info message' do
        event = Shoryuken::Instrumentation::Event.new('app.started', groups: %w[default priority])

        expect(logger).to receive(:info).and_yield.and_return('Shoryuken started with 2 group(s)')

        listener.call(event)
      end
    end

    context 'with app.stopping event' do
      it 'logs info message' do
        event = Shoryuken::Instrumentation::Event.new('app.stopping')

        expect(logger).to receive(:info).and_yield.and_return('Shoryuken shutting down...')

        listener.call(event)
      end
    end

    context 'with app.stopped event' do
      it 'logs info message' do
        event = Shoryuken::Instrumentation::Event.new('app.stopped')

        expect(logger).to receive(:info).and_yield.and_return('Shoryuken stopped')

        listener.call(event)
      end
    end

    context 'with app.quiet event' do
      it 'logs info message' do
        event = Shoryuken::Instrumentation::Event.new('app.quiet')

        expect(logger).to receive(:info).and_yield.and_return('Shoryuken is quiet')

        listener.call(event)
      end
    end

    context 'with fetcher.started event' do
      it 'logs debug message' do
        event = Shoryuken::Instrumentation::Event.new('fetcher.started', queue: 'default', limit: 10)

        expect(logger).to receive(:debug).and_yield.and_return('Looking for new messages in default')

        listener.call(event)
      end
    end

    context 'with fetcher.completed event' do
      it 'logs debug message with message count' do
        event = Shoryuken::Instrumentation::Event.new(
          'fetcher.completed',
          queue: 'default',
          message_count: 5,
          duration_ms: 123.45
        )

        expect(logger).to receive(:debug).twice

        listener.call(event)
      end

      it 'does not log found messages when count is zero' do
        event = Shoryuken::Instrumentation::Event.new(
          'fetcher.completed',
          queue: 'default',
          message_count: 0,
          duration_ms: 50.0
        )

        # Only one debug call for completion, not for "found messages"
        expect(logger).to receive(:debug).once

        listener.call(event)
      end
    end

    context 'with fetcher.retry event' do
      it 'logs debug message with attempt info' do
        event = Shoryuken::Instrumentation::Event.new(
          'fetcher.retry',
          attempt: 2,
          max_attempts: 3,
          error_message: 'Connection timeout'
        )

        expect(logger).to receive(:debug).and_yield.and_return('Retrying fetch attempt 2 for Connection timeout')

        listener.call(event)
      end
    end

    context 'with manager.dispatch event' do
      it 'logs debug message with state info' do
        event = Shoryuken::Instrumentation::Event.new(
          'manager.dispatch',
          group: 'default',
          queue: 'my_queue',
          ready: 5,
          busy: 3,
          active_queues: %w[queue1 queue2]
        )

        expect(logger).to receive(:debug)

        listener.call(event)
      end
    end

    context 'with manager.processor_assigned event' do
      it 'logs debug message with message id' do
        event = Shoryuken::Instrumentation::Event.new(
          'manager.processor_assigned',
          group: 'default',
          queue: 'my_queue',
          message_id: 'msg-123'
        )

        expect(logger).to receive(:debug).and_yield.and_return('Assigning msg-123')

        listener.call(event)
      end
    end

    context 'with manager.failed event' do
      it 'logs error message and backtrace' do
        event = Shoryuken::Instrumentation::Event.new(
          'manager.failed',
          group: 'default',
          error_message: 'Something went wrong',
          backtrace: ['line1', 'line2']
        )

        expect(logger).to receive(:error).twice

        listener.call(event)
      end

      it 'handles missing backtrace' do
        event = Shoryuken::Instrumentation::Event.new(
          'manager.failed',
          group: 'default',
          error_message: 'Something went wrong'
        )

        expect(logger).to receive(:error).once

        listener.call(event)
      end
    end

    context 'with message.processed event' do
      it 'logs info message with duration' do
        event = Shoryuken::Instrumentation::Event.new(
          'message.processed',
          queue: 'default',
          worker: 'TestWorker',
          duration: 0.12345
        )

        expect(logger).to receive(:info).and_yield.and_return('Processed TestWorker/default in 123.45ms')

        listener.call(event)
      end

      it 'handles missing duration' do
        event = Shoryuken::Instrumentation::Event.new(
          'message.processed',
          queue: 'default',
          worker: 'TestWorker'
        )

        expect(logger).to receive(:info)

        listener.call(event)
      end

      it 'does not log when exception is present' do
        event = Shoryuken::Instrumentation::Event.new(
          'message.processed',
          queue: 'default',
          worker: 'TestWorker',
          duration: 0.12345,
          exception: ['StandardError', 'test error']
        )

        expect(logger).not_to receive(:info)

        listener.call(event)
      end
    end

    context 'with message.failed event' do
      it 'logs error message' do
        error = StandardError.new('Something went wrong')
        event = Shoryuken::Instrumentation::Event.new(
          'message.failed',
          queue: 'default',
          worker: 'TestWorker',
          error: error
        )

        expect(logger).to receive(:error).and_yield.and_return('Failed TestWorker/default: Something went wrong')

        listener.call(event)
      end
    end

    context 'with error.occurred event' do
      it 'logs error message with class name' do
        error = ArgumentError.new('Invalid argument')
        event = Shoryuken::Instrumentation::Event.new(
          'error.occurred',
          error: error
        )

        expect(logger).to receive(:error).at_least(:once)

        listener.call(event)
      end

      it 'includes type when present' do
        error = ArgumentError.new('Invalid argument')
        event = Shoryuken::Instrumentation::Event.new(
          'error.occurred',
          error: error,
          type: 'message.processed'
        )

        expect(logger).to receive(:error).at_least(:once)

        listener.call(event)
      end

      it 'logs backtrace when present' do
        error = ArgumentError.new('Invalid argument')
        error.set_backtrace(['line1', 'line2'])
        event = Shoryuken::Instrumentation::Event.new(
          'error.occurred',
          error: error
        )

        expect(logger).to receive(:error).twice

        listener.call(event)
      end
    end

    context 'with queue.polling event' do
      it 'logs debug message' do
        event = Shoryuken::Instrumentation::Event.new('queue.polling', queue: 'default')

        expect(logger).to receive(:debug).and_yield.and_return('Polling queue: default')

        listener.call(event)
      end
    end

    context 'with queue.empty event' do
      it 'logs debug message' do
        event = Shoryuken::Instrumentation::Event.new('queue.empty', queue: 'default')

        expect(logger).to receive(:debug).and_yield.and_return('Queue default is empty')

        listener.call(event)
      end
    end

    context 'with unknown event' do
      it 'does not log anything' do
        event = Shoryuken::Instrumentation::Event.new('unknown.event')

        expect(logger).not_to receive(:info)
        expect(logger).not_to receive(:error)
        expect(logger).not_to receive(:debug)

        listener.call(event)
      end
    end
  end
end
