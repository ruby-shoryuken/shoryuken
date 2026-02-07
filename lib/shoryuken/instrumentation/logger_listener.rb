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
        method_name = "on_#{event.name.tr('.', '_')}"
        send(method_name, event) if respond_to?(method_name, true)
      end

      private

      # App lifecycle events

      def on_app_started(event)
        groups = event[:groups] || []
        logger.info { "Shoryuken started with #{groups.size} group(s)" }
      end

      def on_app_stopping(_event)
        logger.info { 'Shoryuken shutting down...' }
      end

      def on_app_stopped(_event)
        logger.info { 'Shoryuken stopped' }
      end

      def on_app_quiet(_event)
        logger.info { 'Shoryuken is quiet' }
      end

      # Fetcher events

      def on_fetcher_started(event)
        logger.debug { "Looking for new messages in #{event[:queue]}" }
      end

      def on_fetcher_completed(event)
        queue = event[:queue]
        message_count = event[:message_count] || 0
        duration_ms = event[:duration_ms]

        logger.debug { "Found #{message_count} messages for #{queue}" } if message_count.positive?
        logger.debug { "Fetcher for #{queue} completed in #{duration_ms} ms" }
      end

      def on_fetcher_retry(event)
        logger.debug { "Retrying fetch attempt #{event[:attempt]} for #{event[:error_message]}" }
      end

      # Manager events

      def on_manager_dispatch(event)
        logger.debug do
          "Ready: #{event[:ready]}, Busy: #{event[:busy]}, Active Queues: #{event[:active_queues]}"
        end
      end

      def on_manager_processor_assigned(event)
        logger.debug { "Assigning #{event[:message_id]}" }
      end

      def on_manager_failed(event)
        logger.error { "Manager failed: #{event[:error_message]}" }
        logger.error { event[:backtrace].join("\n") } if event[:backtrace]
      end

      # Message processing events

      def on_message_processed(event)
        # Skip logging if there was an exception - error.occurred handles that
        return if event[:exception]

        duration_ms = event.duration ? (event.duration * 1000).round(2) : 0
        worker = event[:worker] || 'Unknown'
        queue = event[:queue] || 'Unknown'

        logger.info { "Processed #{worker}/#{queue} in #{duration_ms}ms" }
      end

      def on_message_failed(event)
        worker = event[:worker] || 'Unknown'
        queue = event[:queue] || 'Unknown'
        error = event[:error]
        error_message = error.respond_to?(:message) ? error.message : error.to_s

        logger.error { "Failed #{worker}/#{queue}: #{error_message}" }
      end

      # Error events

      def on_error_occurred(event)
        error = event[:error]
        error_class = error.respond_to?(:class) ? error.class.name : 'Unknown'
        error_message = error.respond_to?(:message) ? error.message : error.to_s
        type = event[:type]

        if type
          logger.error { "Error in #{type}: #{error_class} - #{error_message}" }
        else
          logger.error { "Error occurred: #{error_class} - #{error_message}" }
        end

        logger.error { error.backtrace.join("\n") } if error.respond_to?(:backtrace) && error.backtrace
      end

      # Queue events

      def on_queue_polling(event)
        queue = event[:queue] || 'Unknown'
        logger.debug { "Polling queue: #{queue}" }
      end

      def on_queue_empty(event)
        logger.debug { "Queue #{event[:queue]} is empty" }
      end
    end
  end
end
