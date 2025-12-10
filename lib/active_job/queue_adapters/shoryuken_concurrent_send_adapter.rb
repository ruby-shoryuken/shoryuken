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
      # @return [Concurrent::Promises::Future] the future representing the async operation
      def enqueue(job, options = {})
        send_concurrently(job, options) { |f_job, f_options| super(f_job, f_options) }
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
        Concurrent::Promises
          .future(job, options) { |f_job, f_options| [yield(f_job, f_options), f_job, f_options] }
          .then { |send_message_response, f_job, f_options| success_handler.call(send_message_response, f_job, f_options) }
          .rescue(job, options) { |err, f_job, f_options| error_handler.call(err, f_job, f_options) }
      end
    end
  end
end
