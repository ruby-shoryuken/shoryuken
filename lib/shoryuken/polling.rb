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
        options.empty? ? name : super
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
        unparsed_queues = unparse_queues(queues)
        
        # Mapping of queues to priority values
        @queue_priorities = unparsed_queues
          .to_h

        # Priority ordering of the queues
        @queue_order = unparsed_queues
          .sort_by { |queue, priority| -priority }
          .map(&:first)

        # Pause status of the queues
        @queue_status = @queue_order
          .map { |queue| [queue, [true, nil]] }
          .to_h

        # Most recently used queue
        @current_queue = nil
      end

      def next_queue
        unpause_queues
        @current_queue = next_active_queue
        return nil if @current_queue.nil?
        QueueConfiguration.new(@current_queue, {})
      end

      def messages_found(queue, messages_found)
        if messages_found == 0
          # If no messages are found, we pause a given queue
          pause(queue) 
        else
          # Reset the current queue when messages found to cause priorities to re-run
          @current_queue = nil
        end
      end

      def active_queues
        @queue_status
          .select { |_, status| status.first }
          .map { |queue, _| [queue, @queue_priorities[queue]] }
      end

      private

      def next_active_queue
        return nil unless @queue_order.length > 0

        start = @current_queue.nil? ? 0 : @queue_order.index(@current_queue) + 1
        i = 0

        # Loop through the queue order from the current queue until we find a
        # queue that is next in line and is not paused
        while true
          queue = @queue_order[(start + i) % @queue_order.length]
          active, delay = @queue_status[queue]
          
          i += 1
          return queue if active
          return nil if i >= @queue_order.length # Prevents infinite looping
        end
      end

      def pause(queue)
        return unless delay > 0
        @queue_status[queue] = [false, Time.now + delay]
        logger.debug "Paused '#{queue}'"
      end
 
      def unpause_queues
        # Modifies queue statuses for queues that are now unpaused
        @queue_status = @queue_status.map do |queue, status|
          active, delay = status

          if active
            [queue, [true, nil]]
          elsif Time.now > delay
            logger.debug "Unpaused '#{queue}'"
            @current_queue = nil # Reset the check ordering on un-pause
            [queue, [true, nil]]
          else
            [queue, [false, delay]]
          end
        end.to_h
      end
    end
  end
end
