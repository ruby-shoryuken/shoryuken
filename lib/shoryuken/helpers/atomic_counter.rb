# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread-safe counter implementation using Ruby's Mutex.
    # Drop-in replacement for Concurrent::AtomicFixnum without external dependencies.
    class AtomicCounter
      def initialize(initial_value = 0)
        @mutex = Mutex.new
        @value = initial_value
      end

      # Get the current value
      def value
        @mutex.synchronize { @value }
      end

      # Increment the counter by 1
      def increment
        @mutex.synchronize { @value += 1 }
      end

      # Decrement the counter by 1
      def decrement
        @mutex.synchronize { @value -= 1 }
      end
    end
  end
end