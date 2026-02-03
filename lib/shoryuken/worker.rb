# frozen_string_literal: true

module Shoryuken
  # Worker module provides the core functionality for creating Shoryuken workers
  # that process messages from Amazon SQS queues.
  #
  # Including this module in a class provides methods for configuring queue processing,
  # enqueueing jobs, and setting up middleware. Workers can be configured for different
  # processing patterns including single message processing, batch processing, and
  # various retry and visibility timeout strategies.
  #
  # @example Basic worker implementation
  #   class EmailWorker
  #     include Shoryuken::Worker
  #     shoryuken_options queue: 'emails'
  #
  #     def perform(sqs_msg, body)
  #       send_email(body['recipient'], body['subject'], body['content'])
  #     end
  #   end
  #
  # @example Advanced worker with all options
  #   class AdvancedWorker
  #     include Shoryuken::Worker
  #
  #     shoryuken_options queue: 'advanced_queue',
  #                       batch: false,
  #                       auto_delete: true,
  #                       auto_visibility_timeout: true,
  #                       retry_intervals: [1, 5, 25, 125, 625]
  #
  #     server_middleware do |chain|
  #       chain.add MyCustomMiddleware
  #     end
  #
  #     def perform(sqs_msg, body)
  #       # Worker implementation
  #     end
  #   end
  #
  # @see ClassMethods#shoryuken_options Primary configuration method
  # @see ClassMethods#perform_async For enqueueing jobs
  # @see https://github.com/ruby-shoryuken/shoryuken/wiki/Workers Comprehensive worker documentation
  module Worker
    # Sets up the including class with Shoryuken worker functionality
    #
    # @param base [Class] the class including this module
    # @return [void]
    def self.included(base)
      base.extend(ClassMethods)
      base.shoryuken_class_attribute :shoryuken_options_hash
    end

    # Class methods added to classes that include Shoryuken::Worker.
    # Provides methods for configuring the worker, enqueueing jobs, and managing middleware.
    module ClassMethods
      # Enqueues a job to be processed asynchronously by a Shoryuken worker.
      #
      # @param body [Object] The job payload that will be passed to the worker's perform method
      # @param options [Hash] Additional options for job enqueueing
      # @option options [String] :message_group_id FIFO queue group ID for message ordering
      # @option options [String] :message_deduplication_id FIFO queue deduplication ID
      # @option options [Hash] :message_attributes Custom SQS message attributes
      # @return [String] The message ID of the enqueued job
      #
      # @example Basic job enqueueing
      #   MyWorker.perform_async({ user_id: 123, action: 'send_email' })
      #
      # @example FIFO queue with ordering
      #   MyWorker.perform_async(data, message_group_id: 'user_123')
      def perform_async(body, options = {})
        Shoryuken.worker_executor.perform_async(self, body, options)
      end

      # Enqueues a job to be processed after a specified time interval.
      #
      # @param interval [Integer, ActiveSupport::Duration] Delay in seconds, or duration object
      # @param body [Object] The job payload that will be passed to the worker's perform method
      # @param options [Hash] SQS message options for the delayed job
      # @option options [String] :message_group_id FIFO queue group ID for message ordering
      # @option options [String] :message_deduplication_id FIFO queue deduplication ID
      # @option options [Hash] :message_attributes Custom SQS message attributes
      # @return [String] The message ID of the enqueued job
      #
      # @example Delay job by 5 minutes
      #   MyWorker.perform_in(5.minutes, { user_id: 123 })
      #
      # @example Delay job by specific number of seconds
      #   MyWorker.perform_in(300, { user_id: 123 })
      def perform_in(interval, body, options = {})
        Shoryuken.worker_executor.perform_in(self, interval, body, options)
      end

      alias_method :perform_at, :perform_in

      # Configures server-side middleware chain for this worker class.
      # Middleware runs before and after job processing, similar to Rack middleware.
      #
      # @yield [Shoryuken::Middleware::Chain] The middleware chain for configuration
      # @return [Shoryuken::Middleware::Chain] The configured middleware chain
      #
      # @example Adding custom middleware
      #   class MyWorker
      #     include Shoryuken::Worker
      #
      #     server_middleware do |chain|
      #       chain.add MyCustomMiddleware
      #       chain.remove Shoryuken::Middleware::Server::ActiveRecord
      #     end
      #   end
      def server_middleware
        @_server_chain ||= Shoryuken.server_middleware.dup
        yield @_server_chain if block_given?
        @_server_chain
      end

      # Configures worker options including queue assignment, processing behavior,
      # and SQS-specific settings. This is the main configuration method for workers.
      #
      # @param opts [Hash] Configuration options for the worker
      # @option opts [String, Array<String>] :queue Queue name(s) this worker processes
      # @option opts [Boolean] :batch (false) Process messages in batches of up to 10
      # @option opts [Boolean] :auto_delete (false) Automatically delete messages after processing
      # @option opts [Boolean] :auto_visibility_timeout (false) Automatically extend message visibility
      # @option opts [Array<Integer>] :retry_intervals Exponential backoff retry intervals in seconds
      # @option opts [Array<Class>, Proc] :non_retryable_exceptions Exception classes or lambda that should skip retries and delete message immediately
      # @option opts [Hash] :sqs Additional SQS client options
      #
      # @example Basic worker configuration
      #   class MyWorker
      #     include Shoryuken::Worker
      #     shoryuken_options queue: 'my_queue'
      #
      #     def perform(sqs_msg, body)
      #       # Process the message
      #     end
      #   end
      #
      # @example Worker with auto-delete and retries
      #   class ReliableWorker
      #     include Shoryuken::Worker
      #     shoryuken_options queue: 'important_queue',
      #                       auto_delete: true,
      #                       retry_intervals: [1, 5, 25, 125]
      #   end
      #
      # @example Batch processing worker
      #   class BatchWorker
      #     include Shoryuken::Worker
      #     shoryuken_options queue: 'batch_queue', batch: true
      #
      #     def perform(sqs_msgs, bodies)
      #       # Process array of up to 10 messages
      #       bodies.each { |body| process_item(body) }
      #     end
      #   end
      #
      # @example Multiple queues with priorities
      #   class MultiQueueWorker
      #     include Shoryuken::Worker
      #     shoryuken_options queue: ['high_priority', 'low_priority']
      #   end
      #
      # @example Auto-extending visibility timeout for long-running jobs
      #   class LongRunningWorker
      #     include Shoryuken::Worker
      #     shoryuken_options queue: 'slow_queue',
      #                       auto_visibility_timeout: true
      #
      #     def perform(sqs_msg, body)
      #       # Long processing that might exceed visibility timeout
      #       complex_processing(body)
      #     end
      #   end
      #
      # @example Worker with non-retryable exceptions
      #   class ValidationWorker
      #     include Shoryuken::Worker
      #     shoryuken_options queue: 'validation_queue',
      #                       non_retryable_exceptions: [InvalidInputError, RecordNotFoundError]
      #
      #     def perform(sqs_msg, body)
      #       # If InvalidInputError or RecordNotFoundError is raised,
      #       # the message will be deleted immediately instead of retrying
      #       validate_and_process(body)
      #     end
      #   end
      #
      # @example Worker with lambda for dynamic exception classification
      #   class SmartWorker
      #     include Shoryuken::Worker
      #     shoryuken_options queue: 'smart_queue',
      #                       non_retryable_exceptions: ->(error) {
      #                         error.is_a?(ValidationError) || 
      #                         (error.is_a?(NetworkError) && error.message.include?('permanent'))
      #                       }
      #
      #     def perform(sqs_msg, body)
      #       # Lambda receives the exception and returns true if non-retryable
      #       process_with_validation(body)
      #     end
      #   end
      def shoryuken_options(opts = {})
        self.shoryuken_options_hash = get_shoryuken_options.merge(stringify_keys(opts || {}))
        normalize_worker_queue!
      end

      # Checks if automatic visibility timeout extension is enabled for this worker.
      # When enabled, Shoryuken automatically extends the message visibility timeout
      # during processing to prevent the message from becoming visible to other consumers.
      #
      # @return [Boolean] true if auto visibility timeout is enabled
      #
      # @see #shoryuken_options Documentation for enabling auto_visibility_timeout
      def auto_visibility_timeout?
        !!get_shoryuken_options['auto_visibility_timeout']
      end

      # Checks if exponential backoff retry is configured for this worker.
      # When retry intervals are specified, failed jobs will be retried with
      # increasing delays between attempts.
      #
      # @return [Boolean] true if retry intervals are configured
      #
      # @example Configuring exponential backoff
      #   shoryuken_options retry_intervals: [1, 5, 25, 125, 625]
      #   # Will retry after 1s, 5s, 25s, 125s, then 625s before giving up
      #
      # @see #shoryuken_options Documentation for configuring retry_intervals
      def exponential_backoff?
        !!get_shoryuken_options['retry_intervals']
      end

      # Checks if automatic message deletion is enabled for this worker.
      # When enabled, successfully processed messages are automatically deleted
      # from the SQS queue. When disabled, you must manually delete messages
      # or they will become visible again after the visibility timeout.
      #
      # @return [Boolean] true if auto delete is enabled
      #
      # @example Manual message deletion when auto_delete is false
      #   def perform(sqs_msg, body)
      #     process_message(body)
      #     # Manually delete the message after successful processing
      #     sqs_msg.delete
      #   end
      #
      # @see #shoryuken_options Documentation for enabling auto_delete
      def auto_delete?
        !!(get_shoryuken_options['delete'] || get_shoryuken_options['auto_delete'])
      end

      # Returns the shoryuken options for this worker class
      # @return [Hash] the options hash
      def get_shoryuken_options # :nodoc:
        shoryuken_options_hash || Shoryuken.default_worker_options
      end

      # Converts hash keys to strings
      # @param hash [Hash] the hash to convert
      # @return [Hash] hash with string keys
      def stringify_keys(hash) # :nodoc:
        new_hash = {}
        hash.each { |key, value| new_hash[key.to_s] = value }
        new_hash
      end

      # Defines inheritable class attributes for workers
      # @param attrs [Array<Symbol>] attribute names to define
      # @return [void]
      def shoryuken_class_attribute(*attrs) # :nodoc:
        attrs.each do |name|
          singleton_class.instance_eval do
            undef_method(name) if method_defined?(name) || private_method_defined?(name)
          end
          define_singleton_method(name) { nil }

          ivar = "@#{name}"

          singleton_class.instance_eval do
            m = "#{name}="
            undef_method(m) if method_defined?(m) || private_method_defined?(m)
          end

          define_singleton_method("#{name}=") do |val|
            singleton_class.class_eval do
              undef_method(name) if method_defined?(name) || private_method_defined?(name)
              define_method(name) { val }
            end

            # singleton? backwards compatibility for ruby < 2.1
            singleton_klass = respond_to?(:singleton?) ? singleton? : self != ancestors.first

            if singleton_klass
              class_eval do
                undef_method(name) if method_defined?(name) || private_method_defined?(name)
                define_method(name) do
                  if instance_variable_defined? ivar
                    instance_variable_get ivar
                  else
                    singleton_class.send name
                  end
                end
              end
            end
            val
          end

          # instance reader
          undef_method(name) if method_defined?(name) || private_method_defined?(name)
          define_method(name) do
            if instance_variable_defined?(ivar)
              instance_variable_get ivar
            else
              self.class.public_send name
            end
          end

          # instance writer
          m = "#{name}="
          undef_method(m) if method_defined?(m) || private_method_defined?(m)
          attr_writer name
        end
      end

      private

      # Normalizes the queue option and registers the worker
      # @return [void]
      def normalize_worker_queue!
        queue = shoryuken_options_hash['queue']
        if queue.respond_to?(:call)
          queue = queue.call
          shoryuken_options_hash['queue'] = queue
        end

        case shoryuken_options_hash['queue']
        when Array
          shoryuken_options_hash['queue'].map!(&:to_s)
        when Symbol
          shoryuken_options_hash['queue'] = shoryuken_options_hash['queue'].to_s
        end

        [shoryuken_options_hash['queue']].flatten.compact.each(&method(:register_worker))
      end

      # Registers this worker class for a queue
      # @param queue [String] the queue name
      # @return [void]
      def register_worker(queue)
        Shoryuken.register_worker(queue, self)
      end
    end
  end
end
