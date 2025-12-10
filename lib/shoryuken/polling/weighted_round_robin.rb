# frozen_string_literal: true

module Shoryuken
  module Polling
    # A polling strategy that processes queues in weighted round-robin order.
    # Queue weights determine how often each queue is polled relative to others.
    # Queues are temporarily paused when no messages are found.
    class WeightedRoundRobin < BaseStrategy
      # Initializes a new WeightedRoundRobin polling strategy
      #
      # @param queues [Array<String>] array of queue names, with weights indicated by repetition
      # @param delay [Float, nil] delay in seconds before unpausing empty queues
      def initialize(queues, delay = nil)
        @initial_queues = queues
        @queues = queues.dup.uniq
        @paused_queues = []
        @delay = delay
      end

      # Returns the next queue to poll in round-robin order
      #
      # @return [QueueConfiguration, nil] the next queue configuration or nil if all paused
      def next_queue
        unpause_queues
        queue = @queues.shift
        return nil if queue.nil?

        @queues << queue
        QueueConfiguration.new(queue, {})
      end

      # Handles the result of polling a queue, adjusting weight if messages were found
      #
      # @param queue [String] the queue name
      # @param messages_found [Integer] number of messages found
      # @return [void]
      def messages_found(queue, messages_found)
        if messages_found == 0
          pause(queue)
          return
        end

        maximum_weight = maximum_queue_weight(queue)
        current_weight = current_queue_weight(queue)
        if maximum_weight > current_weight
          logger.info { "Increasing #{queue} weight to #{current_weight + 1}, max: #{maximum_weight}" }
          @queues << queue
        end
      end

      # Returns the list of active queues with their current weights
      #
      # @return [Array<Array>] array of [queue_name, weight] pairs
      def active_queues
        unparse_queues(@queues)
      end

      # Called when a message from a queue has been processed
      #
      # @param queue [String] the queue name
      # @return [void]
      def message_processed(queue)
        paused_queue = @paused_queues.find { |_time, name| name == queue }
        return unless paused_queue

        paused_queue[0] = Time.at 0
      end

      private

      # Pauses a queue by removing it from active rotation
      #
      # @param queue [String] the queue name to pause
      # @return [void]
      def pause(queue)
        return unless @queues.delete(queue)

        @paused_queues << [Time.now + delay, queue]
        logger.debug "Paused #{queue}"
      end

      # Unpauses queues whose delay has expired
      #
      # @return [void]
      def unpause_queues
        return if @paused_queues.empty?
        return if Time.now < @paused_queues.first[0]

        pause = @paused_queues.shift
        @queues << pause[1]
        logger.debug "Unpaused #{pause[1]}"
      end

      # Returns the current weight of a queue in the active rotation
      #
      # @param queue [String] the queue name
      # @return [Integer] the current weight
      def current_queue_weight(queue)
        queue_weight(@queues, queue)
      end

      # Returns the maximum configured weight of a queue
      #
      # @param queue [String] the queue name
      # @return [Integer] the maximum weight
      def maximum_queue_weight(queue)
        queue_weight(@initial_queues, queue)
      end

      # Counts how many times a queue appears in the given array
      #
      # @param queues [Array<String>] the array to count in
      # @param queue [String] the queue name to count
      # @return [Integer] the count
      def queue_weight(queues, queue)
        queues.count { |q| q == queue }
      end
    end
  end
end
