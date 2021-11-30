module Shoryuken
  module Polling
    class StrictPriority < BaseStrategy
      def initialize(queues, delay = nil, options = {})
        # Priority ordering of the queues, highest priority first
        @queues = queues
                  .group_by { |q| q }
                  .sort_by { |_, qs| -qs.count }
                  .map(&:first)

        # Pause status of the queues, default to past time (unpaused)
        @paused_until = queues
                        .each_with_object({}) { |queue, h| h[queue] = Time.at(0) }

        @delay = delay
        @interval = options[:interval]
        # Start queues at 0
        reset_next_queue
      end

      def next_queue
        next_queue = next_active_queue
        next_queue.nil? ? nil : QueueConfiguration.new(next_queue, {})
      end

      def messages_found(queue, messages_found)
        if messages_found == 0
          delay_pause(queue)
        elsif interval > 0
          interval_pause(queue, messages_found)
        else
          reset_next_queue
        end
      end

      def active_queues
        @queues
          .reverse
          .map.with_index(1)
          .reject { |q, _| queue_paused?(q) }
          .reverse
      end

      def message_processed(queue)
        return if interval > 0

        logger.debug "Unpausing #{queue}"
        @paused_until[queue] = Time.now
      end

      private

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

      def queues_unpaused_since?
        last = @last_unpause_check
        now = @last_unpause_check = Time.now

        last && @paused_until.values.any? { |t| t > last && t <= now }
      end

      def reset_next_queue
        @next_queue_index = 0
      end

      def queue_paused?(queue)
        @paused_until[queue] > Time.now
      end

      def delay_pause(queue)
        return unless delay > 0

        @paused_until[queue] = Time.now + delay
        logger.debug "Paused #{queue}, no messages found"
      end

      def interval_pause(queue, messages_found)
        return unless interval > 0

        @paused_until[queue] = Time.now + interval * messages_found
        logger.debug "Paused #{queue}, found #{messages_found} messages"
      end

      def interval
        @interval || Shoryuken.options[:interval].to_f
      end
    end
  end
end
