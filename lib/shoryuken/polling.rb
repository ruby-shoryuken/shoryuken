module Shoryuken
  module Polling
    QueueConfiguration = Struct.new(:name, :options) do
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
    end

    class WeightedRoundRobin
      include Util

      def initialize(queues)
        @initial_queues = queues
        @queues = queues.dup.uniq
      end

      def active_queues
        unparse_queues(@queues)
      end

      def next_queue
        queue = @queues.shift
        @queues << queue
        QueueConfiguration.new(queue, {})
      end

      def messages_present(queue)
        return unless (original = original_queue_weight(queue)) > (current = current_queue_weight(queue))

        logger.info "Increasing '#{queue}' weight to #{current + 1}, max: #{original}"
        @queues << queue
      end

      def pause(queue)
        return unless @queues.delete(queue)
        logger.debug "Paused '#{queue}'"
      end

      def restart(queue)
        return if @queues.include?(queue)
        logger.debug "Restarting '#{queue}'"
        @queues << queue
      end

      def ==(other)
        case other
        when Array
          @queues == other
        else
          if other.respond_to?(:active_queues)
            self.active_queues == other.active_queues
          else
            false
          end
        end
      end

      private

      def current_queue_weight(queue)
        queue_weight(@queues, queue)
      end

      def original_queue_weight(queue)
        queue_weight(@initial_queues, queue)
      end

      def queue_weight(queues, queue)
        queues.count { |q| q == queue }
      end
    end
  end
end
