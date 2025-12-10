# frozen_string_literal: true

module Shoryuken
  module Polling
    # A polling strategy that processes queues in strict priority order.
    # Higher priority queues are always processed before lower priority queues.
    # Queues are temporarily paused when no messages are found.
    class StrictPriority < BaseStrategy
      # Initializes a new StrictPriority polling strategy
      #
      # @param queues [Array<String>] array of queue names, with higher priority queues appearing more frequently
      # @param delay [Float, nil] delay in seconds before unpausing empty queues
      def initialize(queues, delay = nil)
        # Priority ordering of the queues, highest priority first
        @queues = queues
                  .group_by { |q| q }
                  .sort_by { |_, qs| -qs.count }
                  .map(&:first)

        # Pause status of the queues, default to past time (unpaused)
        @paused_until = queues
                        .each_with_object({}) { |queue, h| h[queue] = Time.at(0) }

        @delay = delay
        # Start queues at 0
        reset_next_queue
      end

      # Returns the next queue to poll based on strict priority
      #
      # @return [QueueConfiguration, nil] the next queue configuration or nil if all paused
      def next_queue
        next_queue = next_active_queue
        next_queue.nil? ? nil : QueueConfiguration.new(next_queue, {})
      end

      # Handles the result of polling a queue
      #
      # @param queue [String] the queue name
      # @param messages_found [Integer] number of messages found
      # @return [void]
      def messages_found(queue, messages_found)
        if messages_found == 0
          pause(queue)
        else
          reset_next_queue
        end
      end

      # Returns the list of active (non-paused) queues with their priorities
      #
      # @return [Array<Array>] array of [queue_name, priority] pairs
      def active_queues
        @queues
          .reverse
          .map.with_index(1)
          .reject { |q, _| queue_paused?(q) }
          .reverse
      end

      # Called when a message from a queue has been processed
      #
      # @param queue [String] the queue name
      # @return [void]
      def message_processed(queue)
        if queue_paused?(queue)
          logger.debug "Unpausing #{queue}"
          @paused_until[queue] = Time.at 0
        end
      end

      private

      # Finds the next active (non-paused) queue
      #
      # @return [String, nil] the queue name or nil if all paused
      def next_active_queue
        reset_next_queue if queues_unpaused_since?

        size = @queues.length
        size.times do
          queue = @queues[@next_queue_index]
          @next_queue_index = (@next_queue_index + 1) % size
          return queue unless queue_paused?(queue)
        end

        nil
      end

      # Checks if any queues have been unpaused since last check
      #
      # @return [Boolean] true if queues were unpaused
      def queues_unpaused_since?
        last = @last_unpause_check
        now = @last_unpause_check = Time.now

        last && @paused_until.values.any? { |t| t > last && t <= now }
      end

      # Resets the next queue index to start from the highest priority
      #
      # @return [void]
      def reset_next_queue
        @next_queue_index = 0
      end

      # Checks if a queue is currently paused
      #
      # @param queue [String] the queue name
      # @return [Boolean] true if the queue is paused
      def queue_paused?(queue)
        @paused_until[queue] > Time.now
      end

      # Pauses a queue for the configured delay time
      #
      # @param queue [String] the queue name to pause
      # @return [void]
      def pause(queue)
        return unless delay > 0

        @paused_until[queue] = Time.now + delay
        logger.debug "Paused #{queue}"
      end
    end
  end
end
