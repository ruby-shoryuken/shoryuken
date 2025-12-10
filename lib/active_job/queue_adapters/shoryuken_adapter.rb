# frozen_string_literal: true

# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters

require 'shoryuken'
require 'shoryuken/active_job/job_wrapper'

module ActiveJob
  module QueueAdapters
    # == Shoryuken adapter for Active Job
    #
    # To use Shoryuken set the queue_adapter config to +:shoryuken+.
    #
    #   Rails.application.config.active_job.queue_adapter = :shoryuken

    # Determine the appropriate base class based on Rails version
    # This prevents AbstractAdapter autoloading issues in Rails 7.0-7.1
    base = if defined?(Rails) && defined?(Rails::VERSION)
             (Rails::VERSION::MAJOR == 7 && Rails::VERSION::MINOR < 2 ? Object : AbstractAdapter)
           else
             Object
           end

    class ShoryukenAdapter < base
      class << self
        def instance
          # https://github.com/ruby-shoryuken/shoryuken/pull/174#issuecomment-174555657
          @instance ||= new
        end

        def enqueue(job)
          instance.enqueue(job)
        end

        def enqueue_at(job, timestamp)
          instance.enqueue_at(job, timestamp)
        end
      end

      # only required for Rails 7.2.x
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

      def enqueue(job, options = {}) # :nodoc:
        register_worker!(job)

        job.sqs_send_message_parameters.merge! options

        queue = Shoryuken::Client.queues(job.queue_name)
        send_message_params = message queue, job
        job.sqs_send_message_parameters = send_message_params
        queue.send_message send_message_params
      end

      def enqueue_at(job, timestamp) # :nodoc:
        enqueue(job, delay_seconds: calculate_delay(timestamp))
      end

      # Bulk enqueue multiple jobs efficiently using SQS batch API.
      # Called by ActiveJob.perform_all_later (Rails 7.1+).
      #
      # @param jobs [Array<ActiveJob::Base>] jobs to enqueue
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

            queue.send_messages(entries: entries)
            batch.each { |job| job.successfully_enqueued = true }
          end
        end

        jobs.count(&:successfully_enqueued?)
      end

      private

      def calculate_delay(timestamp)
        delay = (timestamp - Time.current.to_f).round
        raise 'The maximum allowed delay is 15 minutes' if delay > 15.minutes

        delay
      end

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

      def register_worker!(job)
        Shoryuken.register_worker(job.queue_name, Shoryuken::ActiveJob::JobWrapper)
      end

      MESSAGE_ATTRIBUTES = {
        'shoryuken_class' => {
          string_value: Shoryuken::ActiveJob::JobWrapper.to_s,
          data_type: 'String'
        }
      }.freeze
    end
  end
end
