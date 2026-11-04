# frozen_string_literal: true

# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters
require_relative 'shoryuken_adapter'

module ActiveJob
  module QueueAdapters
    # Shoryuken concurrent adapter for Active Job.
    #
    # This adapter sends messages asynchronously (ie non-blocking) and allows
    # the caller to set up handlers for both success and failure.
    #
    # @example Setting up the adapter
    #   success_handler = ->(response, job, options) { StatsD.increment("#{job.class.name}.success") }
    #   error_handler = ->(err, job, options) { StatsD.increment("#{job.class.name}.failure") }
    #
    #   adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new(success_handler, error_handler)
    #
    #   config.active_job.queue_adapter = adapter
    class ShoryukenConcurrentSendAdapter < ShoryukenAdapter
      # In-flight send futures of one process and the thread pool that runs them
      PendingSends = Struct.new(:pid, :futures, :pool)
      # Guards pending sends of every instance, so it also exists when a subclass initialize skips super
      PENDING_SENDS_MUTEX = Mutex.new
      private_constant :PendingSends, :PENDING_SENDS_MUTEX

      # Initializes a new concurrent send adapter
      #
      # @param success_handler [Proc, nil] callback for successful enqueues
      # @param error_handler [Proc, nil] callback for failed enqueues
      def initialize(success_handler = nil, error_handler = nil)
        super() if defined?(super)
        @success_handler = success_handler
        @error_handler = error_handler
      end

      # Enqueues a job asynchronously
      #
      # @param job [ActiveJob::Base] the job to enqueue
      # @param options [Hash] SQS message configuration
      # @option options [Integer] :delay_seconds delay before the message becomes visible
      # @option options [String] :message_group_id FIFO queue group ID
      # @option options [String] :message_deduplication_id FIFO queue deduplication ID
      # @return [Shoryuken::Helpers::Future] the future representing the async operation
      def enqueue(job, options = {})
        snapshot = current_attributes_snapshot

        send_concurrently(job, options) do |f_job, f_options|
          with_current_attributes(snapshot) { super(f_job, f_options) }
        end
      end

      # Blocks until all in-flight asynchronous sends have completed.
      #
      # Because {#enqueue} schedules the SQS send on a background thread and returns immediately, jobs enqueued shortly
      # before the process exits can be silently dropped before their send runs. Call this from your shutdown sequence to
      # flush them. Only sends already in flight when it is called are awaited; a failed send counts as finished (it is
      # reported to the error handler).
      #
      # @param timeout [Numeric, nil] maximum seconds to wait; nil waits indefinitely
      # @return [Boolean] true if all pending sends finished, false if the timeout elapsed first
      def wait_for_pending_sends(timeout = nil)
        pending = PENDING_SENDS_MUTEX.synchronize { pending_sends.futures.to_a }
        return true if pending.empty?

        if timeout
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          pending.each do |future|
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0

            future.wait(remaining)
          end
        else
          pending.each(&:wait)
        end

        pending.all?(&:resolved?)
      end

      # Returns the success handler, using a default no-op if not set
      #
      # @return [Proc] the success handler
      def success_handler
        @success_handler ||= ->(_send_message_response, _job, _options) { nil }
      end

      # Returns the error handler, using a default logger if not set
      #
      # @return [Proc] the error handler
      def error_handler
        @error_handler ||= lambda { |error, job, _options|
          Shoryuken.logger.warn("Failed to enqueue job: #{job.inspect} due to error: #{error}")
        }
      end

      private

      # Sends a message on a background thread
      #
      # @param job [ActiveJob::Base] the job to enqueue
      # @param options [Hash] SQS message configuration passed to the enqueue operation
      # @option options [Integer] :delay_seconds delay before the message becomes visible
      # @option options [String] :message_group_id FIFO queue group ID
      # @yield [job, options] the actual enqueue operation
      # @return [Shoryuken::Helpers::Future] the future representing the async operation
      def send_concurrently(job, options, &send)
        future = Shoryuken::Helpers::Future.new
        # Tracked before it runs, so {#wait_for_pending_sends} cannot miss a running send
        sends = PENDING_SENDS_MUTEX.synchronize { pending_sends.tap { |current| current.futures.add(future) } }

        begin
          sends.pool.post do
            future.execute { deliver(job, options, &send) }
          ensure
            PENDING_SENDS_MUTEX.synchronize { sends.futures.delete(future) }
          end
        rescue
          PENDING_SENDS_MUTEX.synchronize { sends.futures.delete(future) }
          raise
        end

        future
      end

      # Runs the enqueue operation and passes its outcome to the success or the error handler
      #
      # @param job [ActiveJob::Base] the job to enqueue
      # @param options [Hash] SQS message configuration passed to the enqueue operation
      # @option options [Integer] :delay_seconds delay before the message becomes visible
      # @option options [String] :message_group_id FIFO queue group ID
      # @yield [job, options] the actual enqueue operation
      # @return [Object] the result of the handler that ran
      def deliver(job, options)
        success_handler.call(yield(job, options), job, options)
      rescue => e
        error_handler.call(e, job, options)
      end

      # Returns the in-flight sends of the current process. A forked child starts with an empty set and a new thread
      # pool: the parent's futures are resolved by threads that do not exist in the child, so they would stay pending
      # there forever.
      #
      # Callers must hold PENDING_SENDS_MUTEX.
      #
      # @return [PendingSends] the pending sends of this process
      def pending_sends
        unless @pending_sends&.pid == Process.pid
          @pending_sends = PendingSends.new(Process.pid, Set.new, Shoryuken::Helpers::ThreadPool.new)
        end

        @pending_sends
      end
    end
  end
end
