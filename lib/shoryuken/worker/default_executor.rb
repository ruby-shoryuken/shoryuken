# frozen_string_literal: true

module Shoryuken
  module Worker
    # Default executor that sends messages to SQS for asynchronous processing.
    # This is the standard executor used in production environments.
    class DefaultExecutor
      class << self
        # Enqueues a job for asynchronous processing via SQS
        #
        # @param worker_class [Class] the worker class that will process the message
        # @param body [Object] the message body
        # @param options [Hash] additional SQS message options
        # @option options [Hash] :message_attributes custom message attributes
        # @option options [String] :queue override the default queue
        # @return [Aws::SQS::Types::SendMessageResult] the send result
        # @raise [ArgumentError] if no :queue is given and the worker has several queues
        def perform_async(worker_class, body, options = {})
          # Work on a copy: callers may reuse the same options hash across
          # enqueues, and mutating it (deleting :queue, adding :message_body)
          # would silently reroute or corrupt later jobs. Merge - rather than
          # mutate - the nested :message_attributes hash for the same reason.
          options = options.dup
          options[:message_attributes] = (options[:message_attributes] || {}).merge(
            'shoryuken_class' => {
              string_value: worker_class.to_s,
              data_type: 'String'
            }
          )

          options[:message_body] = body

          queue = options.delete(:queue) || default_queue(worker_class)

          Shoryuken::Client.queues(queue).send_message(options)
        end

        # Enqueues a job for delayed processing via SQS
        #
        # @param worker_class [Class] the worker class that will process the message
        # @param interval [Integer, Float] delay in seconds or timestamp
        # @param body [Object] the message body
        # @param options [Hash] SQS message options for the delayed job
        # @option options [Hash] :message_attributes custom message attributes
        # @option options [String] :queue override the default queue
        # @return [Aws::SQS::Types::SendMessageResult] the send result
        # @raise [Errors::InvalidDelayError] if delay exceeds 15 minutes
        # @raise [Errors::FifoDelayNotSupportedError] if a delay is used with a FIFO queue
        # @raise [ArgumentError] if no :queue is given and the worker has several queues
        # @note A time in the past or a negative interval is sent with a delay of 0
        def perform_in(worker_class, interval, body, options = {})
          interval = interval.to_f
          now = Time.now.to_f
          ts = (interval < 1_000_000_000 ? (now + interval).to_f : interval)

          delay = (ts - now).ceil

          raise Errors::InvalidDelayError, 'The maximum allowed delay is 15 minutes' if delay > 15 * 60

          delay = [delay, 0].max

          if delay.positive?
            queue = Shoryuken::Client.queues(options[:queue] || default_queue(worker_class))

            if queue.fifo?
              raise(
                Errors::FifoDelayNotSupportedError,
                "FIFO queue '#{queue.name}' does not support per-message delays"
              )
            end
          end

          worker_class.perform_async(body, options.merge(delay_seconds: delay))
        end

        private

        # Returns the queue to send to when no :queue option is given
        #
        # @param worker_class [Class] the worker class
        # @return [String] the worker's queue
        # @raise [ArgumentError] if the worker has several queues
        def default_queue(worker_class)
          queue = worker_class.get_shoryuken_options['queue']

          return queue unless queue.is_a?(Array)
          return queue.first if queue.size <= 1

          raise(
            ArgumentError,
            "#{worker_class} has several queues (#{queue.join(', ')}): pass the queue: option to choose one"
          )
        end
      end
    end
  end
end
