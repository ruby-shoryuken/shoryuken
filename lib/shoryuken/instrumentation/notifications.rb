# frozen_string_literal: true

module Shoryuken
  module Instrumentation
    # A thread-safe pub/sub notification system for instrumentation events.
    # Inspired by Karafka's instrumentation architecture, this allows external
    # systems (APM, logging, metrics) to subscribe to Shoryuken lifecycle events.
    #
    # @example Subscribing to specific events
    #   Shoryuken.monitor.subscribe('message.processed') do |event|
    #     StatsD.timing('shoryuken.process_time', event.duration * 1000)
    #   end
    #
    # @example Subscribing to all events
    #   Shoryuken.monitor.subscribe do |event|
    #     logger.info("Event: #{event.name}")
    #   end
    #
    # @example Instrumenting a block
    #   Shoryuken.monitor.instrument('message.processed', queue: 'default') do
    #     process_message
    #   end
    #
    class Notifications
      # List of all supported events in the system
      EVENTS = %w[
        app.started
        app.stopping
        app.stopped
        app.quiet

        fetcher.started
        fetcher.completed
        fetcher.retry

        manager.dispatch
        manager.processor_assigned
        manager.processor_done
        manager.utilization_changed
        manager.failed

        message.received
        message.processed
        message.failed
        message.deleted

        worker.started
        worker.completed
        worker.failed

        queue.polling
        queue.empty

        error.occurred
      ].freeze

      # Creates a new Notifications instance
      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      # Subscribes to events
      #
      # @param event_name [String, nil] the event name to subscribe to, or nil for all events
      # @yield [Event] block called when matching events are published
      # @return [void]
      #
      # @example Subscribe to specific event
      #   subscribe('message.processed') { |event| puts event.name }
      #
      # @example Subscribe to all events
      #   subscribe { |event| puts event.name }
      def subscribe(event_name = nil, &block)
        @mutex.synchronize do
          if event_name
            @subscribers[event_name] << block
          else
            @subscribers[:all] << block
          end
        end
      end

      # Unsubscribes a block from events
      #
      # @param event_name [String, nil] the event name to unsubscribe from, or nil for all events
      # @param block [Proc] the block to unsubscribe
      # @return [void]
      def unsubscribe(event_name = nil, &block)
        @mutex.synchronize do
          key = event_name || :all
          @subscribers[key].delete(block)
        end
      end

      # Instruments a block of code, measuring its duration and publishing an event.
      # Compatible with ActiveSupport::Notifications - if an exception occurs,
      # it adds :exception and :exception_object to the payload and re-raises.
      #
      # Additionally, on exception, publishes a separate 'error.occurred' event
      # (Karafka-style) with a :type key indicating the original event name.
      #
      # @param event_name [String] the event name to publish
      # @param payload [Hash] additional data to include in the event
      # @yield [payload] the code block to instrument (payload is yielded for modification)
      # @return [Object] the result of the block
      #
      # @example Basic usage
      #   monitor.instrument('message.processed', queue: 'default') do
      #     worker.perform(message)
      #   end
      #
      # @example Checking for exceptions in subscriber
      #   monitor.subscribe('message.processed') do |event|
      #     if event[:exception]
      #       # Handle error case
      #       Sentry.capture_exception(event[:exception_object])
      #     else
      #       # Handle success case
      #       StatsD.timing('process_time', event.duration)
      #     end
      #   end
      #
      # @example Subscribing to all errors (Karafka-style)
      #   monitor.subscribe('error.occurred') do |event|
      #     Sentry.capture_exception(event[:error], extra: { type: event[:type] })
      #   end
      def instrument(event_name, payload = {})
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        exception_raised = nil
        begin
          result = yield payload if block_given?
        rescue Exception => e
          exception_raised = e
          payload[:exception] = [e.class.name, e.message]
          payload[:exception_object] = e
          raise e
        ensure
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          event = Event.new(event_name, payload.merge(duration: duration))
          publish(event)

          # Publish a separate error.occurred event (Karafka-style) for centralized error handling
          if exception_raised
            error_payload = payload.merge(
              type: event_name,
              error: exception_raised,
              error_class: exception_raised.class.name,
              error_message: exception_raised.message,
              duration: duration
            )
            publish('error.occurred', error_payload)
          end
        end
        result
      end

      # Publishes an event to all matching subscribers
      #
      # @param event_or_name [Event, String] an Event instance or event name
      # @param payload [Hash] payload hash (only used if first arg is a String)
      # @return [void]
      #
      # @example With Event instance
      #   publish(Event.new('message.processed', queue: 'default'))
      #
      # @example With name and payload
      #   publish('message.processed', queue: 'default')
      def publish(event_or_name, payload = {})
        event = event_or_name.is_a?(Event) ? event_or_name : Event.new(event_or_name, payload)

        subscribers_for_event = @mutex.synchronize do
          @subscribers[event.name] + @subscribers[:all]
        end

        subscribers_for_event.each do |subscriber|
          subscriber.call(event)
        rescue StandardError => e
          # Log but don't raise - subscribers should not break the main flow
          Shoryuken.logger.error { "Instrumentation subscriber error: #{e.message}" }
          Shoryuken.logger.error { e.backtrace.join("\n") } if e.backtrace
        end
      end

      # Clears all subscribers (useful for testing)
      #
      # @return [void]
      def clear
        @mutex.synchronize do
          @subscribers.clear
        end
      end

      # Returns the number of subscribers for an event
      #
      # @param event_name [String, nil] the event name, or nil for global subscribers
      # @return [Integer] the subscriber count
      def subscriber_count(event_name = nil)
        @mutex.synchronize do
          key = event_name || :all
          @subscribers[key].size
        end
      end
    end
  end
end
