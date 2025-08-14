# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Polling::BaseStrategy do
  # Create a concrete implementation for testing
  let(:test_strategy_class) do
    Class.new(described_class) do
      def initialize(queues, delay = nil)
        @queues = queues
        @delay = delay
      end

      def next_queue
        @queues.first
      end

      def messages_found(queue, messages_found)
        # Test implementation - store the call
        @last_messages_found = { queue: queue, count: messages_found }
      end

      def active_queues
        @queues
      end

      attr_reader :last_messages_found
    end
  end

  let(:strategy) { test_strategy_class.new(['queue1', 'queue2']) }

  describe 'abstract interface' do
    it 'includes Util module' do
      expect(described_class.included_modules).to include(Shoryuken::Util)
    end

    describe '#next_queue' do
      it 'raises NotImplementedError in base class' do
        base_strategy = described_class.new

        expect { base_strategy.next_queue }.to raise_error(NotImplementedError)
      end

      it 'can be implemented by subclasses' do
        expect(strategy.next_queue).to eq('queue1')
      end
    end

    describe '#messages_found' do
      it 'raises NotImplementedError in base class' do
        base_strategy = described_class.new

        expect { base_strategy.messages_found('queue', 5) }.to raise_error(NotImplementedError)
      end

      it 'can be implemented by subclasses' do
        strategy.messages_found('test_queue', 3)

        expect(strategy.last_messages_found).to eq({ queue: 'test_queue', count: 3 })
      end

      it 'accepts zero messages found' do
        strategy.messages_found('empty_queue', 0)

        expect(strategy.last_messages_found).to eq({ queue: 'empty_queue', count: 0 })
      end
    end

    describe '#message_processed' do
      it 'has default empty implementation' do
        base_strategy = described_class.new

        expect { base_strategy.message_processed('queue') }.not_to raise_error
      end

      it 'can be overridden by subclasses' do
        # Default implementation should do nothing
        expect { strategy.message_processed('queue') }.not_to raise_error
      end
    end

    describe '#active_queues' do
      it 'raises NotImplementedError in base class' do
        base_strategy = described_class.new

        expect { base_strategy.active_queues }.to raise_error(NotImplementedError)
      end

      it 'can be implemented by subclasses' do
        expect(strategy.active_queues).to eq(['queue1', 'queue2'])
      end
    end
  end

  describe '#==' do
    context 'when comparing with Array' do
      it 'compares against @queues instance variable' do
        expect(strategy).to eq(['queue1', 'queue2'])
      end

      it 'returns false for different arrays' do
        expect(strategy).not_to eq(['queue3', 'queue4'])
      end

      it 'returns false for arrays with different order' do
        expect(strategy).not_to eq(['queue2', 'queue1'])
      end
    end

    context 'when comparing with another strategy' do
      it 'compares active_queues when other responds to active_queues' do
        other_strategy = test_strategy_class.new(['queue1', 'queue2'])

        expect(strategy).to eq(other_strategy)
      end

      it 'returns false when active_queues differ' do
        other_strategy = test_strategy_class.new(['queue3', 'queue4'])

        expect(strategy).not_to eq(other_strategy)
      end

      it 'handles strategies with different active_queues order' do
        other_strategy = test_strategy_class.new(['queue2', 'queue1'])

        expect(strategy).not_to eq(other_strategy)
      end
    end

    context 'when comparing with objects that do not respond to active_queues' do
      it 'returns false for strings' do
        expect(strategy).not_to eq('some_string')
      end

      it 'returns false for numbers' do
        expect(strategy).not_to eq(123)
      end

      it 'returns false for hashes' do
        expect(strategy).not_to eq({ queues: ['queue1', 'queue2'] })
      end

      it 'returns false for objects without active_queues method' do
        plain_object = Object.new

        expect(strategy).not_to eq(plain_object)
      end
    end

    context 'when @queues is not set' do
      let(:strategy_without_queues) { test_strategy_class.new(nil) }

      it 'handles nil @queues when comparing with nil' do
        # nil is not an Array, so this goes to the else branch
        # nil doesn't respond to active_queues, so it returns false
        expect(strategy_without_queues == nil).to be false
      end

      it 'handles nil @queues when comparing with empty array' do
        expect(strategy_without_queues == []).to be false
      end
    end
  end

  describe '#delay' do
    context 'when delay is set on strategy' do
      let(:strategy_with_delay) { test_strategy_class.new(['queue1'], 5.0) }

      it 'returns the strategy-specific delay' do
        expect(strategy_with_delay.delay).to eq(5.0)
      end
    end

    context 'when delay is not set on strategy' do
      before do
        allow(Shoryuken.options).to receive(:[]).with(:delay).and_return(3.5)
      end

      it 'returns the global Shoryuken delay converted to float' do
        expect(strategy.delay).to eq(3.5)
      end
    end

    context 'when global delay is a string' do
      before do
        allow(Shoryuken.options).to receive(:[]).with(:delay).and_return('2.5')
      end

      it 'converts string delay to float' do
        expect(strategy.delay).to eq(2.5)
      end
    end

    context 'when global delay is an integer' do
      before do
        allow(Shoryuken.options).to receive(:[]).with(:delay).and_return(4)
      end

      it 'converts integer delay to float' do
        expect(strategy.delay).to eq(4.0)
      end
    end

    context 'when delay is explicitly set to nil' do
      let(:strategy_with_nil_delay) { test_strategy_class.new(['queue1'], nil) }

      before do
        allow(Shoryuken.options).to receive(:[]).with(:delay).and_return(1.5)
      end

      it 'falls back to global delay' do
        expect(strategy_with_nil_delay.delay).to eq(1.5)
      end
    end
  end

  describe 'inheritance patterns' do
    it 'allows subclasses to call super for implemented methods' do
      subclass = Class.new(described_class) do
        def next_queue
          begin
            super
          rescue NotImplementedError
            'fallback'
          end
        end

        def active_queues
          []
        end

        def messages_found(queue, count)
          # Implementation required
        end
      end

      instance = subclass.new
      expect(instance.next_queue).to eq('fallback')
    end

    it 'supports method chaining in subclasses' do
      chainable_strategy = Class.new(described_class) do
        def initialize(queues)
          @queues = queues
          @call_chain = []
        end

        def next_queue
          @call_chain << :next_queue
          @queues.first
        end

        def messages_found(queue, count)
          @call_chain << :messages_found
          self
        end

        def active_queues
          @call_chain << :active_queues
          @queues
        end

        attr_reader :call_chain
      end

      strategy = chainable_strategy.new(['test'])
      result = strategy.messages_found('queue', 1)

      expect(result).to be(strategy)
      expect(strategy.call_chain).to eq([:messages_found])
    end
  end

  describe 'utility method access' do
    it 'provides access to utility methods through Util module' do
      # Verify that utility methods are available
      expect(strategy).to respond_to(:unparse_queues)
      expect(strategy).to respond_to(:logger)
    end
  end
end