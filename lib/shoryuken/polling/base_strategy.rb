# frozen_string_literal: true

module Shoryuken
  # Polling strategies for determining which queue to fetch messages from next
  module Polling
    # Abstract base class for queue polling strategies.
    #
    # This class defines the interface that all polling strategies must implement
    # to manage queue selection and message flow control in Shoryuken workers.
    # Polling strategies determine which queue to fetch messages from next and
    # how to handle scenarios where queues have no messages available.
    #
    # @abstract Subclass and override {#next_queue}, {#messages_found}, and {#active_queues}
    #   to implement a custom polling strategy.
    #
    # @example Implementing a custom polling strategy
    #   class CustomStrategy < BaseStrategy
    #     def initialize(queues)
    #       @queues = queues
    #     end
    #
    #     def next_queue
    #       # Return next queue to poll
    #       @queues.sample
    #     end
    #
    #     def messages_found(queue, count)
    #       # Handle result of polling
    #       logger.info "Found #{count} messages in #{queue}"
    #     end
    #
    #     def active_queues
    #       # Return list of active queues
    #       @queues
    #     end
    #   end
    #
    # @see WeightedRoundRobin
    # @see StrictPriority
    class BaseStrategy
      include Util

      # Returns the next queue to poll for messages.
      #
      # This method should return a QueueConfiguration object representing
      # the next queue that should be polled for messages, or nil if no
      # queues are currently available for polling.
      #
      # @abstract Subclasses must implement this method
      # @return [QueueConfiguration, nil] Next queue to poll, or nil if none available
      # @raise [NotImplementedError] if not implemented by subclass
      def next_queue
        fail NotImplementedError
      end

      # Called when messages are found (or not found) in a queue.
      #
      # This method is invoked after polling a queue to inform the strategy
      # about the number of messages that were retrieved. Strategies can use
      # this information to make decisions about future polling behavior,
      # such as pausing empty queues or adjusting queue weights.
      #
      # @abstract Subclasses must implement this method
      # @param _queue [String] The name of the queue that was polled
      # @param _messages_found [Integer] The number of messages retrieved
      # @raise [NotImplementedError] if not implemented by subclass
      def messages_found(_queue, _messages_found)
        fail NotImplementedError
      end

      # Called when a message from a queue has been processed.
      #
      # This optional callback is invoked after a message has been successfully
      # processed by a worker. Strategies can use this information for cleanup
      # or to adjust their polling behavior.
      #
      # @param _queue [String] The name of the queue whose message was processed
      # @return [void]
      def message_processed(_queue); end

      # Returns the list of currently active queues.
      #
      # This method should return an array representing the queues that are
      # currently active and available for polling. The format may vary by
      # strategy implementation.
      #
      # @abstract Subclasses must implement this method
      # @return [Array] List of active queues
      # @raise [NotImplementedError] if not implemented by subclass
      def active_queues
        fail NotImplementedError
      end

      # Compares this strategy with another object for equality.
      #
      # Two strategies are considered equal if they have the same active queues.
      # This method also supports comparison with Array objects for backward
      # compatibility.
      #
      # @param other [Object] Object to compare with
      # @return [Boolean] true if strategies are equivalent
      def ==(other)
        case other
        when Array
          @queues == other
        else
          if other.respond_to?(:active_queues)
            active_queues == other.active_queues
          else
            false
          end
        end
      end

      # Returns the delay time for pausing empty queues.
      #
      # This method returns the amount of time (in seconds) that empty queues
      # should be paused before being polled again. The delay can be set at
      # the strategy level or falls back to the global Shoryuken delay setting.
      #
      # @return [Float] Delay time in seconds
      def delay
        @delay || Shoryuken.options[:delay].to_f
      end
    end
  end
end
