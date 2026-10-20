# frozen_string_literal: true

module Shoryuken
  module Instrumentation
    # Default listener that logs instrumentation events.
    # This provides human-readable log output for key Shoryuken events.
    #
    # @example Subscribing the logger listener
    #   Shoryuken.monitor.subscribe(&LoggerListener.new.method(:call))
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
      # @param event [Event] the event; its name selects the `on_*` handler that logs it
      # @return [void]
      def call(event)
        method_name = "on_#{event.name.tr('.', '_')}"
        send(method_name, event) if respond_to?(method_name, true)
      end

      private

      # App lifecycle events

      # Logs that Shoryuken started, with the number of processing groups
      #
      # @param event [Shoryuken::Instrumentation::Event] the app.started event
      # @return [void]
      def on_app_started(event)
        groups = event[:groups] || []
        logger.info { "Shoryuken started with #{groups.size} group(s)" }
      end

      # Logs that Shoryuken is shutting down
      #
      # @param _event [Shoryuken::Instrumentation::Event] the app.stopping event
      # @return [void]
      def on_app_stopping(_event)
        logger.info { 'Shoryuken shutting down...' }
      end

      # Logs that Shoryuken stopped
      #
      # @param _event [Shoryuken::Instrumentation::Event] the app.stopped event
      # @return [void]
      def on_app_stopped(_event)
        logger.info { 'Shoryuken stopped' }
      end

      # Logs that Shoryuken is quiet
      #
      # @param _event [Shoryuken::Instrumentation::Event] the app.quiet event
      # @return [void]
      def on_app_quiet(_event)
        logger.info { 'Shoryuken is quiet' }
      end

      # Fetcher events

      # Logs that the fetcher is looking for messages in a queue
      #
      # @param event [Shoryuken::Instrumentation::Event] the fetcher.started event
      # @return [void]
      def on_fetcher_started(event)
        logger.debug { "Looking for new messages in #{event[:queue]}" }
      end

      # Logs how many messages a fetch found and how long it took
      #
      # @param event [Shoryuken::Instrumentation::Event] the fetcher.completed event
      # @return [void]
      def on_fetcher_completed(event)
        queue = event[:queue]
        message_count = event[:message_count] || 0
        duration_ms = event[:duration_ms]

        logger.debug { "Found #{message_count} messages for #{queue}" } if message_count.positive?
        logger.debug { "Fetcher for #{queue} completed in #{duration_ms} ms" }
      end

      # Logs a retried fetch attempt
      #
      # @param event [Shoryuken::Instrumentation::Event] the fetcher.retry event
      # @return [void]
      def on_fetcher_retry(event)
        logger.debug { "Retrying fetch attempt #{event[:attempt]} for #{event[:error_message]}" }
      end

      # Manager events

      # Logs the ready and busy processors and the active queues on dispatch
      #
      # @param event [Shoryuken::Instrumentation::Event] the manager.dispatch event
      # @return [void]
      def on_manager_dispatch(event)
        logger.debug do
          "Ready: #{event[:ready]}, Busy: #{event[:busy]}, Active Queues: #{event[:active_queues]}"
        end
      end

      # Logs the message assigned to a processor
      #
      # @param event [Shoryuken::Instrumentation::Event] the manager.processor_assigned event
      # @return [void]
      def on_manager_processor_assigned(event)
        logger.debug { "Assigning #{event[:message_id]}" }
      end

      # Logs a manager failure with its backtrace
      #
      # @param event [Shoryuken::Instrumentation::Event] the manager.failed event
      # @return [void]
      def on_manager_failed(event)
        logger.error { "Manager failed: #{event[:error_message]}" }
        logger.error { event[:backtrace].join("\n") } if event[:backtrace]
      end

      # Message processing events

      # Logs a processed message with its duration, unless processing raised
      #
      # @param event [Shoryuken::Instrumentation::Event] the message.processed event
      # @return [void]
      def on_message_processed(event)
        # Skip logging if there was an exception - error.occurred handles that
        return if event[:exception]

        duration_ms = event.duration ? (event.duration * 1000).round(2) : 0
        worker = event[:worker] || 'Unknown'
        queue = event[:queue] || 'Unknown'

        logger.info { "Processed #{worker}/#{queue} in #{duration_ms}ms" }
      end

      # Logs a message that failed to process
      #
      # @param event [Shoryuken::Instrumentation::Event] the message.failed event
      # @return [void]
      def on_message_failed(event)
        worker = event[:worker] || 'Unknown'
        queue = event[:queue] || 'Unknown'
        error = event[:error]
        error_message = error.respond_to?(:message) ? error.message : error.to_s

        logger.error { "Failed #{worker}/#{queue}: #{error_message}" }
      end

      # Error events

      # Logs an error with its type and backtrace
      #
      # @param event [Shoryuken::Instrumentation::Event] the error.occurred event
      # @return [void]
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

      # Logs that a queue is being polled
      #
      # @param event [Shoryuken::Instrumentation::Event] the queue.polling event
      # @return [void]
      def on_queue_polling(event)
        queue = event[:queue] || 'Unknown'
        logger.debug { "Polling queue: #{queue}" }
      end

      # Logs that a queue is empty
      #
      # @param event [Shoryuken::Instrumentation::Event] the queue.empty event
      # @return [void]
      def on_queue_empty(event)
        logger.debug { "Queue #{event[:queue]} is empty" }
      end
    end
  end
end
