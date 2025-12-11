# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Instrumentation::LoggerListener do
  let(:logger) { instance_double(Logger, info: nil, error: nil, debug: nil) }
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

        expect(logger).to receive(:error).and_yield.and_return('Error occurred: ArgumentError - Invalid argument')

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
