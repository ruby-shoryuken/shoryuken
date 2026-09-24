# frozen_string_literal: true

module Shoryuken
  module Instrumentation
    # Represents an instrumentation event with metadata.
    # Events are published through the Notifications system and contain
    # information about what happened, when, and relevant context.
    #
    # @example Creating an event
    #   event = Event.new('message.processed', queue: 'default', duration: 0.5)
    #   event.name      # => 'message.processed'
    #   event[:queue]   # => 'default'
    #   event.duration  # => 0.5
    #
    class Event
      # @return [String] the event name (e.g., 'message.processed')
      attr_reader :name

      # @return [Hash] the event payload containing contextual data
      attr_reader :payload

      # @return [Time] when the event was created
      attr_reader :time

      # Creates a new Event instance
      #
      # @param name [String] the event name using dot notation (e.g., 'message.processed')
      # @param payload [Hash] contextual data for the event
      def initialize(name, payload = {})
        @name = name
        @payload = payload
        @time = Time.now
      end

      # Accesses a value from the payload by key
      #
      # @param key [Symbol, String] the payload key
      # @return [Object, nil] the value or nil if not found
      def [](key)
        payload[key]
      end

      # Returns the duration from the payload if present
      #
      # @return [Float, nil] the duration in seconds or nil
      def duration
        payload[:duration]
      end

      # Returns a hash representation of the event
      #
      # @return [Hash] the event as a hash
      def to_h
        {
          name: name,
          payload: payload,
          time: time
        }
      end
    end
  end
end
