# frozen_string_literal: true

module Shoryuken
  module Middleware
    module Server
      # Middleware that handles non-retryable exceptions by deleting messages immediately.
      # When a configured exception occurs, the message is deleted instead of being retried.
      #
      # Configure non-retryable exceptions per worker:
      #
      #   class MyWorker
      #     include Shoryuken::Worker
      #
      #     # Using exception classes
      #     shoryuken_options queue: 'my_queue',
      #                       non_retryable_exceptions: [InvalidInputError, RecordNotFoundError]
      #
      #     # Or using a lambda for dynamic classification
      #     shoryuken_options queue: 'my_queue',
      #                       non_retryable_exceptions: ->(error) { error.is_a?(StandardError) && error.message.include?('permanent') }
      #
      #     def perform(sqs_msg, body)
      #       # ...
      #     end
      #   end
      class NonRetryableException
        include Util

        # Processes a message and handles non-retryable exceptions
        #
        # @param worker [Object] the worker instance
        # @param queue [String] the queue name
        # @param sqs_msg [Shoryuken::Message, Array<Shoryuken::Message] the message or batch
        # @param _body [Object] the parsed message body (unused)
        # @yield continues to the next middleware in the chain
        # @return [void]
        def call(worker, queue, sqs_msg, _body)
          yield
        rescue => e
          non_retryable_exceptions = worker.class.get_shoryuken_options['non_retryable_exceptions']

          return raise unless non_retryable_exceptions

          if non_retryable_exceptions.respond_to?(:call)
            return raise unless non_retryable_exceptions.call(e)
          else
            exception_classes = Array(non_retryable_exceptions)
            return raise unless exception_classes.any? { |klass| e.is_a?(klass) }
          end

          # Handle batch messages
          messages = sqs_msg.is_a?(Array) ? sqs_msg : [sqs_msg]

          logger.warn do
            "Non-retryable exception #{e.class} occurred for message(s) #{messages.map(&:message_id).join(', ')}. " \
            "Deleting message(s) immediately. Error: #{e.message}"
          end

          logger.debug { e.backtrace.join("\n") } if e.backtrace

          # Delete the message(s) immediately
          entries = messages.map.with_index { |message, i| { id: i.to_s, receipt_handle: message.receipt_handle } }
          Shoryuken::Client.queues(queue).delete_messages(entries: entries)

          # Don't re-raise - the exception has been handled by deleting the message
        end
      end
    end
  end
end

