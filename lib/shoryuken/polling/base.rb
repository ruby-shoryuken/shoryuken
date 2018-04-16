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

      def messages_found(_queue, _messages_found)
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
  end
end
