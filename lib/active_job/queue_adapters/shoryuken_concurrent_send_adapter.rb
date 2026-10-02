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
      # Initializes a new concurrent send adapter
      #
      # @param success_handler [Proc, nil] callback for successful enqueues
      # @param error_handler [Proc, nil] callback for failed enqueues
      def initialize(success_handler = nil, error_handler = nil)
        super() if defined?(super)
        @success_handler = success_handler
        @error_handler = error_handler
        @pending_sends = Set.new
        @pending_sends_mutex = Mutex.new
      end

      # Enqueues a job asynchronously
      #
      # @param job [ActiveJob::Base] the job to enqueue
      # @param options [Hash] SQS message configuration
      # @option options [Integer] :delay_seconds delay before the message becomes visible
      # @option options [String] :message_group_id FIFO queue group ID
      # @option options [String] :message_deduplication_id FIFO queue deduplication ID
      # @return [Concurrent::Promises::Future] the future representing the async operation
      def enqueue(job, options = {})
        send_concurrently(job, options) { |f_job, f_options| super(f_job, f_options) }
      end

      # Blocks until all in-flight asynchronous sends have completed.
      #
      # Because {#enqueue} schedules the SQS send on a background future and
      # returns immediately, jobs enqueued shortly before the process exits can
      # be silently dropped before their send runs. Call this from your shutdown
      # sequence to flush them.
      #
      # @param timeout [Numeric, nil] maximum seconds to wait; nil waits indefinitely
      # @return [Boolean] true if all pending sends finished, false if the timeout elapsed first
      def wait_for_pending_sends(timeout = nil)
        pending = @pending_sends_mutex.synchronize { @pending_sends.to_a }
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

      # Sends a message concurrently using futures
      #
      # @param job [ActiveJob::Base] the job to enqueue
      # @param options [Hash] SQS message configuration passed to the enqueue operation
      # @option options [Integer] :delay_seconds delay before the message becomes visible
      # @option options [String] :message_group_id FIFO queue group ID
      # @yield [job, options] the actual enqueue operation
      # @return [Concurrent::Promises::Future] the future representing the async operation
      def send_concurrently(job, options)
        future = Concurrent::Promises
                 .future(job, options) { |f_job, f_options| [yield(f_job, f_options), f_job, f_options] }
                 .then { |response, f_job, f_options| success_handler.call(response, f_job, f_options) }
                 .rescue(job, options) { |err, f_job, f_options| error_handler.call(err, f_job, f_options) }

        track_pending_send(future)
      end

      # Tracks an in-flight send future so {#wait_for_pending_sends} can await it,
      # removing it once it resolves to keep the set from growing unbounded.
      #
      # @param future [Concurrent::Promises::Future] the send future to track
      # @return [Concurrent::Promises::Future] the same future
      def track_pending_send(future)
        @pending_sends_mutex.synchronize { @pending_sends.add(future) }
        future.on_resolution! { @pending_sends_mutex.synchronize { @pending_sends.delete(future) } }
        future
      end
    end
  end
end
