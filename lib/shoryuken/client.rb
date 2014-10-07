module Shoryuken
  class Client
    @@queues = {}
    @@visibility_timeouts = {}

    class << self
      def queues(queue_name)
        @@queues[queue_name.to_s] ||= sqs.queues.named(queue_name)
      end

      def visibility_timeout(queue_name)
        @@visibility_timeouts[queue_name.to_s] ||= queues(queue_name).visibility_timeout
      end

      def receive_message(queue_name, options = {})
        queues(queue_name).receive_message(Hash(options))
      end

      def reset!
        # for test purposes
        @@queues = {}
      end

      def sqs
        @sqs ||= AWS::SQS.new
      end
    end
  end
end
