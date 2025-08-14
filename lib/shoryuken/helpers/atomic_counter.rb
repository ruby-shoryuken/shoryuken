# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread-safe counter implementation using Ruby's Mutex.
    #
    # This class provides atomic operations for incrementing, decrementing, and reading
    # integer values in a thread-safe manner. It serves as a drop-in replacement for
    # Concurrent::AtomicFixnum without requiring external dependencies.
    #
    # The implementation uses a Mutex to ensure thread safety across all Ruby
    # implementations including JRuby, where true parallelism makes atomic operations
    # critical for data integrity.
    #
    # @note This class is optimized for scenarios with frequent atomic updates
    #   and occasional reads, such as tracking active worker counts.
    #
    # @example Basic usage
    #   counter = Shoryuken::Helpers::AtomicCounter.new(0)
    #   counter.increment  # => 1
    #   counter.increment  # => 2
    #   counter.value      # => 2
    #   counter.decrement  # => 1
    #
    # @example Tracking busy processors
    #   @busy_processors = Shoryuken::Helpers::AtomicCounter.new(0)
    #
    #   # When starting work
    #   @busy_processors.increment
    #
    #   # When work is done
    #   @busy_processors.decrement
    #
    #   # Check current load
    #   current_busy = @busy_processors.value
    class AtomicCounter
      # Creates a new atomic counter with the specified initial value.
      #
      # @param initial_value [Integer] The starting value for the counter
      # @return [AtomicCounter] A new atomic counter instance
      #
      # @example Create counter starting at zero
      #   counter = Shoryuken::Helpers::AtomicCounter.new
      #   counter.value  # => 0
      #
      # @example Create counter with custom initial value
      #   counter = Shoryuken::Helpers::AtomicCounter.new(100)
      #   counter.value  # => 100
      def initialize(initial_value = 0)
        @mutex = Mutex.new
        @value = initial_value
      end

      # Returns the current value of the counter.
      #
      # This operation is thread-safe and will return a consistent value
      # even when called concurrently with increment/decrement operations.
      #
      # @return [Integer] The current counter value
      #
      # @example Reading the current value
      #   counter = Shoryuken::Helpers::AtomicCounter.new(42)
      #   counter.value  # => 42
      def value
        @mutex.synchronize { @value }
      end

      # Atomically increments the counter by 1 and returns the new value.
      #
      # This operation is thread-safe and can be called concurrently from
      # multiple threads without risk of data corruption or lost updates.
      #
      # @return [Integer] The new counter value after incrementing
      #
      # @example Incrementing the counter
      #   counter = Shoryuken::Helpers::AtomicCounter.new(5)
      #   counter.increment  # => 6
      #   counter.increment  # => 7
      def increment
        @mutex.synchronize { @value += 1 }
      end

      # Atomically decrements the counter by 1 and returns the new value.
      #
      # This operation is thread-safe and can be called concurrently from
      # multiple threads without risk of data corruption or lost updates.
      # The counter can go negative if decremented below zero.
      #
      # @return [Integer] The new counter value after decrementing
      #
      # @example Decrementing the counter
      #   counter = Shoryuken::Helpers::AtomicCounter.new(5)
      #   counter.decrement  # => 4
      #   counter.decrement  # => 3
      #
      # @example Counter can go negative
      #   counter = Shoryuken::Helpers::AtomicCounter.new(0)
      #   counter.decrement  # => -1
      def decrement
        @mutex.synchronize { @value -= 1 }
      end
    end
  end
end