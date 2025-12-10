# frozen_string_literal: true

module Shoryuken
  module Worker
    # Executor that processes jobs synchronously in the current thread.
    # Useful for testing and development environments.
    class InlineExecutor
      class << self
        # Processes a job synchronously in the current thread
        #
        # @param worker_class [Class] the worker class that will process the message
        # @param body [Object] the message body
        # @param options [Hash] inline execution options
        # @option options [String] :queue override the default queue name
        # @option options [Hash] :message_attributes custom message attributes
        # @return [Object] the result of the worker's perform method
        def perform_async(worker_class, body, options = {})
          body = JSON.dump(body) if body.is_a?(Hash)
          queue_name = options.delete(:queue) || worker_class.get_shoryuken_options['queue']
          message_attributes = options.delete(:message_attributes) || {}
          message_attributes['shoryuken_class'] = {
            string_value: worker_class.to_s,
            data_type: 'String'
          }

          sqs_msg = InlineMessage.new(
            body: body,
            attributes: nil,
            md5_of_body: nil,
            md5_of_message_attributes: nil,
            message_attributes: message_attributes,
            message_id: nil,
            receipt_handle: nil,
            delete: nil,
            queue_name: queue_name
          )

          call(worker_class, sqs_msg)
        end

        # Processes a job synchronously, ignoring the delay interval
        #
        # @param worker_class [Class] the worker class that will process the message
        # @param _interval [Integer, Float] ignored for inline execution
        # @param body [Object] the message body
        # @param options [Hash] inline execution options
        # @option options [String] :queue override the default queue name
        # @option options [Hash] :message_attributes custom message attributes
        # @return [Object] the result of the worker's perform method
        def perform_in(worker_class, _interval, body, options = {})
          worker_class.perform_async(body, options)
        end

        private

        # Instantiates and calls the worker
        #
        # @param worker_class [Class] the worker class
        # @param sqs_msg [Shoryuken::InlineMessage] the message
        # @return [Object] the result of the worker's perform method
        def call(worker_class, sqs_msg)
          parsed_body = BodyParser.parse(worker_class, sqs_msg)
          batch = worker_class.shoryuken_options_hash['batch']
          args = batch ? [[sqs_msg], [parsed_body]] : [sqs_msg, parsed_body]
          worker_class.new.perform(*args)
        end
      end
    end
  end
end
