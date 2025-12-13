# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Instrumentation::Notifications do
  let(:notifications) { described_class.new }

  after do
    notifications.clear
  end

  describe '#subscribe' do
    it 'subscribes to specific event' do
      events = []
      notifications.subscribe('message.processed') { |e| events << e }

      notifications.publish('message.processed', queue: 'default')
      notifications.publish('message.failed', queue: 'default')

      expect(events.size).to eq(1)
      expect(events.first.name).to eq('message.processed')
    end

    it 'subscribes to all events when no event name given' do
      events = []
      notifications.subscribe { |e| events << e }

      notifications.publish('message.processed', queue: 'default')
      notifications.publish('message.failed', queue: 'default')

      expect(events.size).to eq(2)
    end

    it 'allows multiple subscribers for same event' do
      counter = { a: 0, b: 0 }
      notifications.subscribe('message.processed') { counter[:a] += 1 }
      notifications.subscribe('message.processed') { counter[:b] += 1 }

      notifications.publish('message.processed')

      expect(counter[:a]).to eq(1)
      expect(counter[:b]).to eq(1)
    end
  end

  describe '#unsubscribe' do
    it 'removes subscriber from specific event' do
      events = []
      block = ->(e) { events << e }
      notifications.subscribe('message.processed', &block)

      notifications.publish('message.processed')
      expect(events.size).to eq(1)

      notifications.unsubscribe('message.processed', &block)
      notifications.publish('message.processed')
      expect(events.size).to eq(1)
    end

    it 'removes global subscriber' do
      events = []
      block = ->(e) { events << e }
      notifications.subscribe(&block)

      notifications.publish('message.processed')
      expect(events.size).to eq(1)

      notifications.unsubscribe(&block)
      notifications.publish('message.processed')
      expect(events.size).to eq(1)
    end
  end

  describe '#instrument' do
    it 'executes the block' do
      result = notifications.instrument('message.processed') { 'hello' }
      expect(result).to eq('hello')
    end

    it 'publishes event with duration' do
      events = []
      notifications.subscribe('message.processed') { |e| events << e }

      notifications.instrument('message.processed', queue: 'default') { sleep 0.01 }

      expect(events.size).to eq(1)
      expect(events.first.duration).to be >= 0.01
      expect(events.first[:queue]).to eq('default')
    end

    it 'publishes event even without block' do
      events = []
      notifications.subscribe('message.processed') { |e| events << e }

      notifications.instrument('message.processed', queue: 'default')

      expect(events.size).to eq(1)
      expect(events.first.duration).to be_a(Float)
    end

    it 'yields payload to allow modification' do
      events = []
      notifications.subscribe('message.processed') { |e| events << e }

      notifications.instrument('message.processed', queue: 'default') do |payload|
        payload[:custom_key] = 'custom_value'
      end

      expect(events.first[:custom_key]).to eq('custom_value')
    end

    context 'when exception occurs (ActiveSupport-compatible)' do
      it 'adds :exception to payload with class name and message' do
        events = []
        notifications.subscribe('message.processed') { |e| events << e }

        expect do
          notifications.instrument('message.processed', queue: 'default') do
            raise ArgumentError, 'invalid argument'
          end
        end.to raise_error(ArgumentError, 'invalid argument')

        expect(events.size).to eq(1)
        expect(events.first[:exception]).to eq(['ArgumentError', 'invalid argument'])
      end

      it 'adds :exception_object to payload' do
        events = []
        notifications.subscribe('message.processed') { |e| events << e }

        expect do
          notifications.instrument('message.processed', queue: 'default') do
            raise StandardError, 'test error'
          end
        end.to raise_error(StandardError)

        expect(events.first[:exception_object]).to be_a(StandardError)
        expect(events.first[:exception_object].message).to eq('test error')
      end

      it 'still publishes event with duration' do
        events = []
        notifications.subscribe('message.processed') { |e| events << e }

        expect do
          notifications.instrument('message.processed', queue: 'default') do
            sleep 0.01
            raise 'error'
          end
        end.to raise_error(RuntimeError)

        expect(events.first.duration).to be >= 0.01
      end

      it 're-raises the exception' do
        expect do
          notifications.instrument('message.processed') do
            raise ArgumentError, 'test'
          end
        end.to raise_error(ArgumentError, 'test')
      end
    end

    context 'when exception occurs (Karafka-style error.occurred)' do
      it 'publishes error.occurred event with type key' do
        error_events = []
        notifications.subscribe('error.occurred') { |e| error_events << e }

        expect do
          notifications.instrument('message.processed', queue: 'default') do
            raise StandardError, 'test error'
          end
        end.to raise_error(StandardError)

        expect(error_events.size).to eq(1)
        expect(error_events.first[:type]).to eq('message.processed')
      end

      it 'includes error object in error.occurred event' do
        error_events = []
        notifications.subscribe('error.occurred') { |e| error_events << e }

        expect do
          notifications.instrument('message.processed', queue: 'default') do
            raise ArgumentError, 'invalid argument'
          end
        end.to raise_error(ArgumentError)

        expect(error_events.first[:error]).to be_a(ArgumentError)
        expect(error_events.first[:error].message).to eq('invalid argument')
      end

      it 'includes error_class and error_message in error.occurred event' do
        error_events = []
        notifications.subscribe('error.occurred') { |e| error_events << e }

        expect do
          notifications.instrument('message.processed', queue: 'default') do
            raise RuntimeError, 'something went wrong'
          end
        end.to raise_error(RuntimeError)

        expect(error_events.first[:error_class]).to eq('RuntimeError')
        expect(error_events.first[:error_message]).to eq('something went wrong')
      end

      it 'includes original payload in error.occurred event' do
        error_events = []
        notifications.subscribe('error.occurred') { |e| error_events << e }

        expect do
          notifications.instrument('message.processed', queue: 'default', worker: 'TestWorker') do
            raise StandardError, 'test error'
          end
        end.to raise_error(StandardError)

        expect(error_events.first[:queue]).to eq('default')
        expect(error_events.first[:worker]).to eq('TestWorker')
      end

      it 'includes duration in error.occurred event' do
        error_events = []
        notifications.subscribe('error.occurred') { |e| error_events << e }

        expect do
          notifications.instrument('message.processed', queue: 'default') do
            sleep 0.01
            raise StandardError, 'test error'
          end
        end.to raise_error(StandardError)

        expect(error_events.first[:duration]).to be >= 0.01
      end

      it 'does not publish error.occurred on success' do
        error_events = []
        notifications.subscribe('error.occurred') { |e| error_events << e }

        notifications.instrument('message.processed', queue: 'default') { 'success' }

        expect(error_events).to be_empty
      end
    end
  end

  describe '#publish' do
    it 'publishes event by name and payload' do
      events = []
      notifications.subscribe('message.processed') { |e| events << e }

      notifications.publish('message.processed', queue: 'default')

      expect(events.size).to eq(1)
      expect(events.first.name).to eq('message.processed')
      expect(events.first[:queue]).to eq('default')
    end

    it 'publishes existing Event instance' do
      events = []
      notifications.subscribe('message.processed') { |e| events << e }

      event = Shoryuken::Instrumentation::Event.new('message.processed', queue: 'default')
      notifications.publish(event)

      expect(events.size).to eq(1)
      expect(events.first).to eq(event)
    end

    it 'does not raise when subscriber raises' do
      notifications.subscribe('message.processed') { raise 'boom' }

      expect { notifications.publish('message.processed') }.not_to raise_error
    end

    it 'logs error when subscriber raises' do
      notifications.subscribe('message.processed') { raise 'boom' }

      expect(Shoryuken.logger).to receive(:error).at_least(:once)
      notifications.publish('message.processed')
    end

    it 'continues to other subscribers when one raises' do
      events = []
      notifications.subscribe('message.processed') { raise 'boom' }
      notifications.subscribe('message.processed') { |e| events << e }

      notifications.publish('message.processed')

      expect(events.size).to eq(1)
    end
  end

  describe '#clear' do
    it 'removes all subscribers' do
      notifications.subscribe('message.processed') { }
      notifications.subscribe { }

      expect(notifications.subscriber_count('message.processed')).to eq(1)
      expect(notifications.subscriber_count).to eq(1)

      notifications.clear

      expect(notifications.subscriber_count('message.processed')).to eq(0)
      expect(notifications.subscriber_count).to eq(0)
    end
  end

  describe '#subscriber_count' do
    it 'returns count for specific event' do
      notifications.subscribe('message.processed') { }
      notifications.subscribe('message.processed') { }
      notifications.subscribe('message.failed') { }

      expect(notifications.subscriber_count('message.processed')).to eq(2)
      expect(notifications.subscriber_count('message.failed')).to eq(1)
    end

    it 'returns count for global subscribers' do
      notifications.subscribe { }
      notifications.subscribe { }

      expect(notifications.subscriber_count).to eq(2)
    end

    it 'returns 0 for events with no subscribers' do
      expect(notifications.subscriber_count('nonexistent')).to eq(0)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent subscriptions' do
      threads = 10.times.map do
        Thread.new do
          10.times do
            notifications.subscribe('message.processed') { }
          end
        end
      end

      threads.each(&:join)

      expect(notifications.subscriber_count('message.processed')).to eq(100)
    end

    it 'handles concurrent publishing' do
      counter = Concurrent::AtomicFixnum.new(0)
      notifications.subscribe('message.processed') { counter.increment }

      threads = 10.times.map do
        Thread.new do
          10.times { notifications.publish('message.processed') }
        end
      end

      threads.each(&:join)

      expect(counter.value).to eq(100)
    end
  end
end
