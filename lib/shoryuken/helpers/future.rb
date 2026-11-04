# frozen_string_literal: true

module Shoryuken
  module Helpers
    # The result of a block run on another thread.
    # Replacement for Concurrent::Promises::Future without external dependencies.
    class Future
      # Initializes a new unresolved Future
      def initialize
        @mutex = Mutex.new
        @resolution = ConditionVariable.new
        @resolved = false
        @value = nil
        @reason = nil
      end

      # Runs the block and resolves the Future with its result, or with its error when it raises
      #
      # @yield the block to run
      # @return [Future] self
      def execute
        value = yield
        resolve(value, nil)
        self
      rescue Exception => e
        resolve(nil, e)
        self
      end

      # Checks if the block has finished
      #
      # @return [Boolean] true once the block has returned or raised
      def resolved?
        @resolved
      end

      # Checks if the block has returned without an error
      #
      # @return [Boolean] true if the Future is resolved without an error
      def fulfilled?
        @resolved && @reason.nil?
      end

      # Checks if the block has raised
      #
      # @return [Boolean] true if the Future is resolved with an error
      def rejected?
        @resolved && !@reason.nil?
      end

      # Waits for the Future to resolve
      #
      # @param timeout [Numeric, nil] maximum seconds to wait; nil waits indefinitely
      # @return [Boolean] true if the Future is resolved, false if the timeout elapsed first
      def wait(timeout = nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout

        @mutex.synchronize do
          until @resolved
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC) if deadline
            break if remaining && remaining <= 0

            @resolution.wait(@mutex, remaining)
          end

          @resolved
        end
      end

      # Waits for the Future to resolve and returns the block's result
      #
      # @param timeout [Numeric, nil] maximum seconds to wait; nil waits indefinitely
      # @return [Object, nil] the block's result, or nil if it raised or the timeout elapsed first
      def value(timeout = nil)
        wait(timeout)
        @value
      end

      # Waits for the Future to resolve and returns the block's error
      #
      # @param timeout [Numeric, nil] maximum seconds to wait; nil waits indefinitely
      # @return [Exception, nil] the error the block raised, or nil if it did not raise or the timeout elapsed first
      def reason(timeout = nil)
        wait(timeout)
        @reason
      end

      private

      # Stores the result and wakes the waiting threads
      #
      # @param value [Object, nil] the block's result
      # @param reason [Exception, nil] the block's error
      # @return [void]
      def resolve(value, reason)
        @mutex.synchronize do
          @value = value
          @reason = reason
          @resolved = true
          @resolution.broadcast
        end
      end
    end
  end
end
