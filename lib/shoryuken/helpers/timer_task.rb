# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread-safe timer task implementation.
    # Drop-in replacement for Concurrent::TimerTask without external dependencies.
    class TimerTask
      def initialize(execution_interval:, &block)
        @execution_interval = execution_interval
        @task_block = block
        @mutex = Mutex.new
        @thread = nil
        @running = false
        @killed = false
      end

      # Start the timer task execution
      def execute
        @mutex.synchronize do
          return self if @running || @killed

          @running = true
          @thread = Thread.new { run_timer_loop }
        end
        self
      end

      # Stop and kill the timer task
      def kill
        @mutex.synchronize do
          return false if @killed

          @killed = true
          @running = false

          if @thread && @thread.alive?
            @thread.kill
            @thread.join(1) # Wait up to 1 second for clean shutdown
          end
        end
        true
      end

      private

      def run_timer_loop
        while !@killed
          sleep(@execution_interval)
          break if @killed

          begin
            @task_block.call
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
