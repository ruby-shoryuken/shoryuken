# frozen_string_literal: true

module Shoryuken
  module Instrumentation
    # Default listener that logs instrumentation events.
    # This provides human-readable log output for key Shoryuken events.
    #
    # @example Subscribing the logger listener
    #   Shoryuken.monitor.subscribe(&LoggerListener.new.method(:call))
    #
    class LoggerListener
      # Creates a new LoggerListener
      #
      # @param logger [Logger] the logger to use (defaults to Shoryuken.logger)
      def initialize(logger = nil)
        @logger = logger
      end

      # Returns the logger instance
      #
      # @return [Logger] the logger
      def logger
        @logger || Shoryuken.logger
      end

      # Handles an instrumentation event by logging it appropriately
      #
      # @param event [Event] the event to handle
      # @return [void]
      def call(event)
        case event.name
        when 'app.started'
          log_app_started(event)
        when 'app.stopping'
          log_app_stopping(event)
        when 'app.stopped'
          log_app_stopped(event)
        when 'message.processed'
          log_message_processed(event)
        when 'message.failed'
          log_message_failed(event)
        when 'error.occurred'
          log_error_occurred(event)
        when 'queue.polling'
          log_queue_polling(event)
        end
      end

      private

      def log_app_started(event)
        groups = event[:groups] || []
        logger.info { "Shoryuken started with #{groups.size} group(s)" }
      end

      def log_app_stopping(_event)
        logger.info { 'Shoryuken shutting down...' }
      end

      def log_app_stopped(_event)
        logger.info { 'Shoryuken stopped' }
      end

      def log_message_processed(event)
        duration_ms = event.duration ? (event.duration * 1000).round(2) : 0
        worker = event[:worker] || 'Unknown'
        queue = event[:queue] || 'Unknown'

        logger.info { "Processed #{worker}/#{queue} in #{duration_ms}ms" }
      end

      def log_message_failed(event)
        worker = event[:worker] || 'Unknown'
        queue = event[:queue] || 'Unknown'
        error = event[:error]
        error_message = error.respond_to?(:message) ? error.message : error.to_s

        logger.error { "Failed #{worker}/#{queue}: #{error_message}" }
      end

      def log_error_occurred(event)
        error = event[:error]
        error_class = error.respond_to?(:class) ? error.class.name : 'Unknown'
        error_message = error.respond_to?(:message) ? error.message : error.to_s

        logger.error { "Error occurred: #{error_class} - #{error_message}" }
      end

      def log_queue_polling(event)
        queue = event[:queue] || 'Unknown'
        logger.debug { "Polling queue: #{queue}" }
      end
    end
  end
end
