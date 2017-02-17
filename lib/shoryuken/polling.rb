module Shoryuken
  module Polling
    QueueConfiguration = Struct.new(:name, :options) do
      def hash
        name.hash
      end

      def ==(other)
        case other
        when String
          if options.empty?
            name == other
          else
            false
          end
        else
          super
        end
      end

      alias_method :eql?, :==

      def to_s
        if options.empty?
          name
        else
          "#<QueueConfiguration #{name} options=#{options.inspect}>"
        end
      end
    end

    class BaseStrategy
      include Util

      def next_queue
        fail NotImplementedError
      end

      def messages_found(queue, messages_found)
        fail NotImplementedError
      end

      def active_queues
        fail NotImplementedError
      end

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

      private

      def delay
        Shoryuken.options[:delay].to_f
      end
    end

    class WeightedRoundRobin < BaseStrategy
      def initialize(queues)
        @initial_queues = queues
        @queues = queues.dup.uniq
        @paused_queues = []
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
          logger.info { "Increasing '#{queue}' weight to #{current_weight + 1}, max: #{maximum_weight}" }
          @queues << queue
        end
      end

      def active_queues
        unparse_queues(@queues)
      end

      private

      def pause(queue)
        return unless @queues.delete(queue)
        @paused_queues << [Time.now + delay, queue]
        logger.debug "Paused '#{queue}'"
      end

      def unpause_queues
        return if @paused_queues.empty?
        return if Time.now < @paused_queues.first[0]
        pause = @paused_queues.shift
        @queues << pause[1]
        logger.debug "Unpaused '#{pause[1]}'"
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

    class StrictPriority < BaseStrategy
      def initialize(queues)
        # Priority ordering of the queues, highest priority first
        @queues = queues
          .group_by { |q| q }
          .sort_by { |_, qs| -qs.count }
          .map(&:first)

        # Pause status of the queues, default to past time (unpaused)
        @paused_until = queues
          .each_with_object(Hash.new) { |queue, h| h[queue] = Time.at(0) }

        # Start queues at 0
        reset_next_queue
      end

      def next_queue
        next_queue = next_active_queue
        next_queue.nil? ? nil : QueueConfiguration.new(next_queue, {})
      end

      def messages_found(queue, messages_found)
        if messages_found == 0
          pause(queue)
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

      def pause(queue)
        return unless delay > 0
        @paused_until[queue] = Time.now + delay
        logger.debug "Paused '#{queue}'"
      end
    end
  end
end
