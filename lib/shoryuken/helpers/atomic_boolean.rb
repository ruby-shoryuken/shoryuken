# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread-safe boolean implementation using AtomicCounter as base.
    # Drop-in replacement for Concurrent::AtomicBoolean without external dependencies.
    # Uses 1 for true and 0 for false internally.
    class AtomicBoolean < AtomicCounter
      # Prevent misuse of counter operations on a boolean
      undef_method :increment, :decrement

      def initialize(initial_value = false)
        super(initial_value ? 1 : 0)
      end

      # Get the current value as boolean
      def value
        super != 0
      end

      # Set the value to true
      def make_true
        @mutex.synchronize { @value = 1 }
        true
      end

      # Set the value to false
      def make_false
        @mutex.synchronize { @value = 0 }
        false
      end

      # Check if the value is true
      def true?
        @mutex.synchronize { @value != 0 }
      end

      # Check if the value is false
      def false?
        @mutex.synchronize { @value == 0 }
      end
    end
  end
end
