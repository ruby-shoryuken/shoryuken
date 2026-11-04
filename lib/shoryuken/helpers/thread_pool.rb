# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread pool that grows on demand and reuses idle threads, removing a thread once it has been idle for
    # {IDLE_TIMEOUT} seconds. Replaces Concurrent::CachedThreadPool without external dependencies, and meets the
    # executor contract described in {Shoryuken::Options#launcher_executor}.
    class ThreadPool
      # Seconds an idle thread waits for a new block before it exits
      IDLE_TIMEOUT = 60

      # Initializes a new ThreadPool with no threads
      def initialize
        @mutex = Mutex.new
        @queue = ::Queue.new
        @threads = Set.new
        @idle = 0
        @running = true
      end

      # Runs the block on a pool thread, starting a new thread when none is idle. Returns without waiting for the block.
      # An error raised by the block is logged; it does not stop the thread.
      #
      # @yield the block to run
      # @return [true] once the block is accepted
      # @raise [Shoryuken::Errors::RejectedExecutionError] when the pool is shut down
      def post(&block)
        @mutex.synchronize do
          raise Errors::RejectedExecutionError, 'The thread pool is shut down' unless @running

          if @idle.positive?
            @idle -= 1
            @queue << block
          else
            @threads << Thread.new(block) { |task| work(task) }
          end
        end

        true
      end

      # Checks if the pool accepts new blocks
      #
      # @return [Boolean] false once the pool is shut down
      def running?
        @running
      end

      # Stops accepting new blocks. Blocks already posted still run.
      #
      # @return [void]
      def shutdown
        @mutex.synchronize do
          @running = false
          @queue.close
        end
      end

      # Waits for the pool threads to finish after {#shutdown}
      #
      # @param timeout [Numeric, nil] maximum seconds to wait; nil waits indefinitely
      # @return [Boolean] true if all threads finished, false if the timeout elapsed first
      def wait_for_termination(timeout = nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout
        threads = @mutex.synchronize { @threads.to_a }

        threads.all? do |thread|
          remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max if deadline
          thread.join(remaining)
        end
      end

      # Shuts the pool down, drops the blocks not yet started and kills the threads running blocks
      #
      # @return [void]
      def kill
        threads = @mutex.synchronize do
          @running = false
          @queue.close
          @queue.clear
          @threads.to_a
        end

        # Killed outside the mutex: Thread#kill can hand the GVL to the killed thread before it returns
        threads.each(&:kill)
      end

      private

      # Runs blocks on the current pool thread until the pool shuts down or the thread stays idle for too long
      #
      # @param task [Proc] the first block to run
      # @return [void]
      def work(task)
        while task
          run(task)
          task = next_task
        end
      end

      # Runs a block, logging its error
      #
      # @param task [Proc] the block to run
      # @return [void]
      def run(task)
        task.call
      rescue => e
        Shoryuken.logger.error { "Thread pool block failed: #{e.class.name}: #{e.message}" }
        Shoryuken.logger.debug { e.backtrace.join("\n") } unless e.backtrace.nil?
      end

      # Waits for the next posted block. The mutex is held only with interrupts deferred: a thread killed while it
      # waits for a Mutex can consume the unlock wakeup and leave the other waiters asleep forever.
      #
      # @return [Proc, nil] the next block, or nil when the thread must exit
      def next_task
        Thread.handle_interrupt(Object => :never) { @mutex.synchronize { @idle += 1 } }

        loop do
          task = @queue.pop(timeout: IDLE_TIMEOUT)
          return task if task
          return if @queue.closed?
          return if Thread.handle_interrupt(Object => :never) { @mutex.synchronize { retire_idle_thread } }
        end
      end

      # Removes the current idle thread from the pool unless a posted block has reserved it. Callers must hold the mutex.
      #
      # @return [Boolean] true if the thread was removed and must exit
      def retire_idle_thread
        return false unless @idle.positive?

        @idle -= 1
        @threads.delete(Thread.current)
        true
      end
    end
  end
end
