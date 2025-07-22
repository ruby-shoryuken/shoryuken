# frozen_string_literal: true

module Shoryuken
  module Polling
    class WeightedRoundRobin < BaseStrategy
      def initialize(queues, delay = nil)
        @initial_queues = queues
        @queues = queues.dup.uniq
        @paused_queues = []
        @delay = delay
      end

      def next_queue
        unpause_queues
        queue = @queues.shift
        return nil if queue.nil?

        @queues << queue
        QueueConfiguration.new(queue, {})
      end

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

      def active_queues
        unparse_queues(@queues)
      end

      def message_processed(queue)
        paused_queue = @paused_queues.find { |_time, name| name == queue }
        return unless paused_queue

        paused_queue[0] = Time.at 0
      end

      private

      def pause(queue)
        return unless @queues.delete(queue)

        @paused_queues << [Time.now + delay, queue]
        logger.debug "Paused #{queue}"
      end

      def unpause_queues
        return if @paused_queues.empty?
        return if Time.now < @paused_queues.first[0]

        pause = @paused_queues.shift
        @queues << pause[1]
        logger.debug "Unpaused #{pause[1]}"
      end

      def current_queue_weight(queue)
        queue_weight(@queues, queue)
      end

      def maximum_queue_weight(queue)
        queue_weight(@initial_queues, queue)
      end

      def queue_weight(queues, queue)
        queues.count { |q| q == queue }
      end
    end
  end
end
