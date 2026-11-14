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
    # Example Rails configuration:
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
      # This method is required for ActiveJob Continuations support (Rails 8.1+). When true, it signals to jobs that they
      # should checkpoint their progress and gracefully interrupt execution to allow for resumption after restart.
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

        job.sqs_send_message_parameters = job_parameters(job)
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
      # @raise [Shoryuken::Errors::FifoDelayNotSupportedError] if delay is used with a FIFO queue
      # @raise [Shoryuken::Errors::InvalidDelayError] if delay exceeds 15 minutes
      def enqueue_at(job, timestamp) # :nodoc:
        # Checked before the send, so subclasses that send asynchronously still fail synchronously
        delay = delay_seconds(Shoryuken::Client.queues(job.queue_name), timestamp)

        enqueue(job, delay_seconds: delay)
      end

      # Bulk enqueue multiple jobs efficiently using SQS batch API.
      # Called by ActiveJob.perform_all_later (Rails 7.1+). A job with a scheduled time is delayed as in {#enqueue_at}.
      # Each batch holds up to 10 messages and up to 1 MiB in total.
      #
      # @param jobs [Array<ActiveJob::Base>] array of ActiveJob instances to be enqueued
      # @return [Integer] number of jobs successfully enqueued
      # @raise [Shoryuken::Errors::FifoDelayNotSupportedError] if a job is delayed on a FIFO queue, before any send
      # @raise [Shoryuken::Errors::InvalidDelayError] if a job delay exceeds 15 minutes, before any send
      def enqueue_all(jobs) # :nodoc:
        batches = jobs.group_by(&:queue_name).map do |queue_name, queue_jobs|
          queue = Shoryuken::Client.queues(queue_name)

          [queue, queue_jobs, queue_jobs.map { |job| batch_entry(queue, job) }]
        end

        batches.each do |queue, queue_jobs, entries|
          each_batch(entries) do |start, count|
            batch = entries[start, count]
            batch.each_with_index { |entry, idx| entry[:id] = idx.to_s }

            response = queue.send_messages(entries: batch)
            successful_ids = response.successful.map { |r| r.id.to_i }.to_set
            queue_jobs[start, count].each_with_index do |job, idx|
              job.successfully_enqueued = successful_ids.include?(idx)
            end
          end
        end

        jobs.count(&:successfully_enqueued?)
      end

      private

      # Builds the batch entry of a job, with the body in JSON, and stores its parameters on the job
      #
      # @param queue [Shoryuken::Queue] the queue to send to
      # @param job [ActiveJob::Base] the job to enqueue
      # @return [Hash] the batch entry, without its id
      # @raise [Shoryuken::Errors::FifoDelayNotSupportedError] if the job is delayed on a FIFO queue
      # @raise [Shoryuken::Errors::InvalidDelayError] if the job delay exceeds 15 minutes
      def batch_entry(queue, job)
        register_worker!(job)
        job.sqs_send_message_parameters = job_parameters(job)
        job.sqs_send_message_parameters[:delay_seconds] = delay_seconds(queue, job.scheduled_at.to_f) if job.scheduled_at

        msg = message(queue, job)
        job.sqs_send_message_parameters = msg
        entry = msg.dup
        entry[:message_body] = JSON.dump(entry[:message_body]) if entry[:message_body].is_a?(Hash)
        entry
      end

      # Yields the entries in batches of up to 10 messages and up to 1 MiB in total. A larger entry goes alone.
      #
      # @param entries [Array<Hash>] the batch entries, with the bodies in JSON
      # @yieldparam start [Integer] the index of the first entry of the batch
      # @yieldparam count [Integer] the number of entries in the batch
      # @return [void]
      def each_batch(entries)
        start = 0
        batch_size = 0

        entries.each_with_index do |entry, idx|
          size = entry_size(entry)
          count = idx - start

          if count == MAX_BATCH_MESSAGES || (count.positive? && batch_size + size > MAX_BATCH_BYTES)
            yield start, count
            start = idx
            batch_size = 0
          end

          batch_size += size
        end

        yield start, entries.size - start if entries.size > start
      end

      # Calculates the size SQS counts for a message: its body and its attribute names, types and values
      #
      # @param entry [Hash] the batch entry, with the body in JSON
      # @return [Integer] the size in bytes
      def entry_size(entry)
        size = entry[:message_body].bytesize

        entry[:message_attributes]&.each do |name, value|
          size += name.to_s.bytesize + value[:data_type].to_s.bytesize
          size += (value[:string_value] || value[:binary_value]).to_s.bytesize
        end

        size
      end

      # Calculates the delay of a send at a timestamp, as SQS accepts it
      #
      # @param queue [Shoryuken::Queue] the queue to send to
      # @param timestamp [Float] Unix timestamp when the job should be processed
      # @return [Integer] delay in seconds, 0 for a timestamp in the past
      # @raise [Shoryuken::Errors::FifoDelayNotSupportedError] if the delay is positive and the queue is FIFO
      # @raise [Shoryuken::Errors::InvalidDelayError] if delay exceeds 15 minutes
      def delay_seconds(queue, timestamp)
        delay = calculate_delay(timestamp)

        # FIFO queues do not support per-message delays. Past timestamps are sent with delay_seconds=0
        # (calculate_delay clamps them, as SQS accepts only 0 to 900 seconds)
        # See https://github.com/ruby-shoryuken/shoryuken/issues/924
        if delay.positive? && queue.fifo?
          raise(
            Shoryuken::Errors::FifoDelayNotSupportedError,
            "FIFO queue '#{queue.name}' does not support per-message delays. " \
            'When using ActiveJob retry_on with FIFO queues, set `wait: 0`.'
          )
        end

        delay
      end

      # Calculates the delay in seconds from a timestamp
      #
      # @param timestamp [Float] Unix timestamp
      # @return [Integer] delay in seconds, 0 for a timestamp in the past
      # @raise [Shoryuken::Errors::InvalidDelayError] if delay exceeds 15 minutes
      def calculate_delay(timestamp)
        delay = (timestamp - Time.current.to_f).round
        raise Shoryuken::Errors::InvalidDelayError, 'The maximum allowed delay is 15 minutes' if delay > 15.minutes

        [delay, 0].max
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

        if queue.fifo? && Shoryuken.active_job_fifo_message_deduplication?
          # See https://github.com/ruby-shoryuken/shoryuken/issues/457 and
          # https://github.com/ruby-shoryuken/shoryuken/pull/750#issuecomment-1781317929
          # Disable via Shoryuken.active_job_fifo_message_deduplication = false when distinct
          # enqueues of the same job class and arguments must not be silently deduplicated.
          msg[:message_deduplication_id] = deduplication_id(body)
        end

        msg.merge(job_params.except(:message_attributes))
      end

      # Returns the job's SQS parameters. After a send they are the parameters sent (see #enqueue), so the values that
      # send computed (body, delay, generated deduplication id) are left out: enqueueing the same job again sends its
      # current state, and every other value, including ones changed since, still applies.
      #
      # @param job [ActiveJob::Base] the job being enqueued
      # @return [Hash] the job's SQS parameters
      def job_parameters(job)
        params = job.sqs_send_message_parameters
        body = params[:message_body]
        return params unless body

        kept = params.except(:message_body, :delay_seconds)
        id = kept[:message_deduplication_id]
        kept.delete(:message_deduplication_id) if id && generated_deduplication_id?(body, id)
        kept
      end

      # Checks if a deduplication id is one Shoryuken generated for a sent body: the queue's or the adapter's
      #
      # @param body [Hash, String] the sent message body, a JSON string once the queue has sent it
      # @param id [String] the deduplication id sent with it
      # @return [Boolean] true if Shoryuken generated the id
      def generated_deduplication_id?(body, id)
        json = body.is_a?(String) ? body : JSON.dump(body)
        id == Digest::SHA256.hexdigest(json) || id == deduplication_id(JSON.parse(json))
      end

      # Computes the FIFO deduplication id of a job body, without its job_id and enqueued_at
      #
      # @param body [Hash] the serialized job
      # @return [String] the deduplication id
      def deduplication_id(body)
        Digest::SHA256.hexdigest(JSON.dump(body.except('job_id', 'enqueued_at')))
      end

      # Captures the CurrentAttributes of the caller for a send that runs on another thread. None without
      # Shoryuken::ActiveJob::CurrentAttributes.persist, which overrides it.
      #
      # @return [Hash, nil] the captured attributes
      def current_attributes_snapshot
        nil
      end

      # Runs a send with captured CurrentAttributes set
      #
      # @param _snapshot [Hash, nil] attributes from {#current_attributes_snapshot}
      # @yield the send
      # @return [Object] the block result
      def with_current_attributes(_snapshot)
        yield
      end

      # Registers the JobWrapper as the worker for the job's queue
      #
      # @param job [ActiveJob::Base] the job being enqueued
      # @return [void]
      def register_worker!(job)
        Shoryuken.register_worker(job.queue_name, Shoryuken::ActiveJob::JobWrapper)
      end

      # Maximum number of messages in one SQS batch
      MAX_BATCH_MESSAGES = 10

      # Maximum total size in bytes of one SQS batch
      # @see https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html
      MAX_BATCH_BYTES = 1024 * 1024

      private_constant :MAX_BATCH_MESSAGES, :MAX_BATCH_BYTES

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
