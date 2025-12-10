# frozen_string_literal: true

# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters

require 'shoryuken'
require 'shoryuken/active_job/job_wrapper'

# Rails ActiveJob module providing background job processing
module ActiveJob
  # Queue adapter implementations for various backends
  module QueueAdapters
    # Shoryuken adapter for Active Job.
    # To use Shoryuken set the queue_adapter config to +:shoryuken+.
    #
    # @example Rails configuration
    #   Rails.application.config.active_job.queue_adapter = :shoryuken

    # Determine the appropriate base class based on Rails version
    # This prevents AbstractAdapter autoloading issues in Rails 7.0-7.1
    base = if defined?(Rails) && defined?(Rails::VERSION)
             (Rails::VERSION::MAJOR == 7 && Rails::VERSION::MINOR < 2 ? Object : AbstractAdapter)
           else
             Object
           end

    # Shoryuken queue adapter for ActiveJob integration.
    # Provides methods for enqueueing jobs to SQS queues.
    class ShoryukenAdapter < base
      class << self
        # Returns the singleton adapter instance
        #
        # @return [ShoryukenAdapter] the adapter instance
        def instance
          # https://github.com/ruby-shoryuken/shoryuken/pull/174#issuecomment-174555657
          @instance ||= new
        end

        # Enqueues a job for immediate processing
        #
        # @param job [ActiveJob::Base] the job to enqueue
        # @return [Aws::SQS::Types::SendMessageResult] the send result
        def enqueue(job)
          instance.enqueue(job)
        end

        # Enqueues a job for delayed processing
        #
        # @param job [ActiveJob::Base] the job to enqueue
        # @param timestamp [Float] Unix timestamp when the job should be processed
        # @return [Aws::SQS::Types::SendMessageResult] the send result
        def enqueue_at(job, timestamp)
          instance.enqueue_at(job, timestamp)
        end
      end

      # Checks if jobs should be enqueued after transaction commit (Rails 7.2+)
      #
      # @return [Boolean] always returns true
      def enqueue_after_transaction_commit?
        true
      end

      # Indicates whether Shoryuken is in the process of shutting down.
      #
      # This method is required for ActiveJob Continuations support (Rails 8.1+).
      # When true, it signals to jobs that they should checkpoint their progress
      # and gracefully interrupt execution to allow for resumption after restart.
      #
      # @return [Boolean] true if Shoryuken is shutting down, false otherwise
      # @see https://github.com/rails/rails/pull/55127 Rails ActiveJob Continuations
      def stopping?
        launcher = Shoryuken::Runner.instance.launcher
        launcher&.stopping? || false
      end

      # Enqueues a job for immediate processing
      #
      # @param job [ActiveJob::Base] the job to enqueue
      # @param options [Hash] SQS message configuration
      # @option options [Integer] :delay_seconds delay before the message becomes visible
      # @option options [String] :message_group_id FIFO queue group ID
      # @option options [String] :message_deduplication_id FIFO queue deduplication ID
      # @return [Aws::SQS::Types::SendMessageResult] the send result
      def enqueue(job, options = {}) # :nodoc:
        register_worker!(job)

        job.sqs_send_message_parameters.merge! options

        queue = Shoryuken::Client.queues(job.queue_name)
        send_message_params = message queue, job
        job.sqs_send_message_parameters = send_message_params
        queue.send_message send_message_params
      end

      # Enqueues a job for delayed processing
      #
      # @param job [ActiveJob::Base] the job to enqueue
      # @param timestamp [Float] Unix timestamp when the job should be processed
      # @return [Aws::SQS::Types::SendMessageResult] the send result
      def enqueue_at(job, timestamp) # :nodoc:
        enqueue(job, delay_seconds: calculate_delay(timestamp))
      end

      # Bulk enqueue multiple jobs efficiently using SQS batch API.
      # Called by ActiveJob.perform_all_later (Rails 7.1+).
      #
      # @param jobs [Array<ActiveJob::Base>] array of ActiveJob instances to be enqueued
      # @return [Integer] number of jobs successfully enqueued
      def enqueue_all(jobs) # :nodoc:
        jobs.group_by(&:queue_name).each do |queue_name, queue_jobs|
          queue = Shoryuken::Client.queues(queue_name)

          queue_jobs.each_slice(10) do |batch|
            entries = batch.map.with_index do |job, idx|
              register_worker!(job)
              msg = message(queue, job)
              job.sqs_send_message_parameters = msg
              { id: idx.to_s }.merge(msg)
            end

            response = queue.send_messages(entries: entries)
            successful_ids = response.successful.map { |r| r.id.to_i }.to_set
            batch.each_with_index do |job, idx|
              job.successfully_enqueued = successful_ids.include?(idx)
            end
          end
        end

        jobs.count(&:successfully_enqueued?)
      end

      private

      # Calculates the delay in seconds from a timestamp
      #
      # @param timestamp [Float] Unix timestamp
      # @return [Integer] delay in seconds
      # @raise [RuntimeError] if delay exceeds 15 minutes
      def calculate_delay(timestamp)
        delay = (timestamp - Time.current.to_f).round
        raise 'The maximum allowed delay is 15 minutes' if delay > 15.minutes

        delay
      end

      # Builds the SQS message parameters for a job
      #
      # @param queue [Shoryuken::Queue] the queue to send to
      # @param job [ActiveJob::Base] the job to serialize
      # @return [Hash] the message parameters
      def message(queue, job)
        body = job.serialize
        job_params = job.sqs_send_message_parameters

        attributes = job_params[:message_attributes] || {}

        msg = {
          message_body: body,
          message_attributes: attributes.merge(MESSAGE_ATTRIBUTES)
        }

        if queue.fifo?
          # See https://github.com/ruby-shoryuken/shoryuken/issues/457 and
          # https://github.com/ruby-shoryuken/shoryuken/pull/750#issuecomment-1781317929
          msg[:message_deduplication_id] = Digest::SHA256.hexdigest(
            JSON.dump(body.except('job_id', 'enqueued_at'))
          )
        end

        msg.merge(job_params.except(:message_attributes))
      end

      # Registers the JobWrapper as the worker for the job's queue
      #
      # @param job [ActiveJob::Base] the job being enqueued
      # @return [void]
      def register_worker!(job)
        Shoryuken.register_worker(job.queue_name, Shoryuken::ActiveJob::JobWrapper)
      end

      # Default message attributes identifying the Shoryuken worker class
      MESSAGE_ATTRIBUTES = {
        'shoryuken_class' => {
          string_value: Shoryuken::ActiveJob::JobWrapper.to_s,
          data_type: 'String'
        }
      }.freeze
    end
  end
end
