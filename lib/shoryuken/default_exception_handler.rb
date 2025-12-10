# frozen_string_literal: true

module Shoryuken
  # Default exception handler that logs errors during message processing.
  # Implements a simple error logging strategy that outputs the exception
  # message and backtrace to the configured logger.
  class DefaultExceptionHandler
    extend Util

    # Handles an exception that occurred during message processing
    #
    # @param exception [Exception] the exception that was raised
    # @param _queue [String] the queue name where the error occurred (unused)
    # @param _sqs_msg [Shoryuken::Message] the message being processed (unused)
    # @return [void]
    def self.call(exception, _queue, _sqs_msg)
      logger.error { "Processor failed: #{exception.message}" }
      logger.error { exception.backtrace.join("\n") } if exception.backtrace
    end
  end
end
