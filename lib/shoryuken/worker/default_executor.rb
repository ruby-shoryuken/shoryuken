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
        def perform_async(worker_class, body, options = {})
          options[:message_attributes] ||= {}
          options[:message_attributes]['shoryuken_class'] = {
            string_value: worker_class.to_s,
            data_type: 'String'
          }

          options[:message_body] = body

          queue = options.delete(:queue) || worker_class.get_shoryuken_options['queue']

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
        def perform_in(worker_class, interval, body, options = {})
          interval = interval.to_f
          now = Time.now.to_f
          ts = (interval < 1_000_000_000 ? (now + interval).to_f : interval)

          delay = (ts - now).ceil

          raise Errors::InvalidDelayError, 'The maximum allowed delay is 15 minutes' if delay > 15 * 60

          worker_class.perform_async(body, options.merge(delay_seconds: delay))
        end
      end
    end
  end
end
