# frozen_string_literal: true

module Shoryuken
  module Helpers
    # Runs each posted block as an Async task on one reactor thread, at most `limit` tasks at a time. Used by the fiber
    # executor mode (`Shoryuken.executor = :fiber`) to process the messages of one group. It has the methods the
    # launcher uses on its executor (see {Options#launcher_executor}).
    #
    # The `async` gem is an optional dependency: it is required only when an instance is built.
    class FiberExecutor
      # Builds the executor. The reactor thread starts on the first post
      #
      # @param limit [Integer] the maximum number of blocks that run at once
      # @raise [Errors::InvalidConfigurationError] when the async gem is not available
      def initialize(limit)
        load_async

        @limit = limit
        @queue = ::Queue.new
        @running = AtomicBoolean.new(true)
        @mutex = Mutex.new
        @thread = nil
      end

      # Queues a block to run as an Async task
      #
      # @yield the block to run
      # @return [true]
      # @raise [Concurrent::RejectedExecutionError] when the executor is shut down
      def post(&block)
        raise Concurrent::RejectedExecutionError, 'fiber executor is shut down' unless running?

        start_reactor
        @queue.push(block)
        true
      rescue ClosedQueueError
        raise Concurrent::RejectedExecutionError, 'fiber executor is shut down'
      end

      # Checks if the executor still accepts blocks
      #
      # @return [Boolean] false once the executor is shut down
      def running?
        @running.true?
      end

      # Stops accepting new blocks and lets the queued and running ones finish
      #
      # @return [void]
      def shutdown
        @running.make_false
        @queue.close
      end

      # Waits for the queued and running blocks to finish
      #
      # @param timeout [Numeric, nil] seconds to wait, nil to wait without a limit
      # @return [Boolean] true when they finished
      def wait_for_termination(timeout = nil)
        thread = @mutex.synchronize { @thread }
        return true if thread.nil?

        !thread.join(timeout).nil?
      end

      # Stops the blocks that did not finish
      #
      # @return [void]
      def kill
        @mutex.synchronize { @thread }&.kill
      end

      private

      # Requires the async gem and raises a clear error when it is missing
      #
      # @return [void]
      # @raise [Errors::InvalidConfigurationError] when the async gem is not available
      def load_async
        require 'async'
        require 'async/semaphore'
      rescue LoadError => e
        raise(
          Errors::InvalidConfigurationError,
          "The fiber executor needs the async gem. Add `gem 'async'` to your Gemfile (#{e.message})"
        )
      end

      # Starts the reactor thread unless it runs already
      #
      # @return [void]
      def start_reactor
        @mutex.synchronize do
          @thread ||= Thread.new { run_reactor }
        end
      end

      # Runs every queued block as a task until the executor is shut down and the queue is drained. A full semaphore
      # stops the loop from taking the next block until a task finishes. The reactor returns once every task finished
      #
      # @return [void]
      def run_reactor
        Sync do
          semaphore = Async::Semaphore.new(@limit)

          while (block = @queue.pop)
            semaphore.async { block.call }
          end
        end
      end
    end
  end
end
