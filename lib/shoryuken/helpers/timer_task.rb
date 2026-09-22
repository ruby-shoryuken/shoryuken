# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread-safe timer task implementation.
    # Drop-in replacement for Concurrent::TimerTask without external dependencies.
    class TimerTask
      # Initializes a new TimerTask
      #
      # @param execution_interval [Float] interval in seconds between task executions
      # @param task [Proc] the task to execute on each interval (provided as a block)
      # @return [TimerTask] a new TimerTask instance
      # @raise [ArgumentError] if no block is provided or interval is not positive
      # @yield the task to execute on each interval
      def initialize(execution_interval:, &task)
        raise ArgumentError, 'A block must be provided' unless block_given?

        @execution_interval = Float(execution_interval)
        raise ArgumentError, 'execution_interval must be positive' if @execution_interval <= 0

        @task = task
        @mutex = Mutex.new
        @thread = nil
        @running = false
        @killed = false
      end

      # Starts the timer task execution
      #
      # @return [TimerTask] self for method chaining
      def execute
        @mutex.synchronize do
          return self if @running || @killed

          @running = true
          @thread = Thread.new { run_timer_loop }
        end
        self
      end

      # Stops and kills the timer task
      #
      # @return [Boolean] true if killed, false if already killed
      def kill
        thread_to_kill = nil

        @mutex.synchronize do
          return false if @killed

          @killed = true
          @running = false
          thread_to_kill = @thread
        end

        # Kill the thread AFTER releasing the mutex. The timer loop's ensure
        # block calls @mutex.synchronize to clear @running; killing the thread
        # while holding that mutex deadlocks on Ruby 3.2, where Thread#kill
        # yields the GVL to the killed thread for cleanup before returning.
        thread_to_kill&.kill if thread_to_kill&.alive?
        true
      end

      private

      # Runs the timer loop in a separate thread
      #
      # @return [void]
      def run_timer_loop
        # The timer thread inherits the priority of the thread that called
        # #execute. Shoryuken runs workers at a lowered priority
        # (Shoryuken.thread_priority, default -1) and starts the
        # auto-visibility-extension timer from inside that worker thread, so the
        # timer would otherwise inherit -1. A latency-sensitive timer must not
        # run below normal priority: under CPU contention a delayed extension can
        # miss the visibility timeout and let the message be redelivered (double
        # processed). Reset to normal priority.
        Thread.current.priority = 0

        until @killed
          sleep(@execution_interval)
          break if @killed

          begin
            @task.call
          rescue => e
            # Log the error but continue running
            # This matches the behavior of Concurrent::TimerTask
            warn "TimerTask execution error: #{e.message}"
            warn e.backtrace.join("\n") if e.backtrace
          end
        end
      ensure
        @mutex.synchronize { @running = false }
      end
    end
  end
end
