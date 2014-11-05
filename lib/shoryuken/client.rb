module Shoryuken
  class Client
    @@queues = {}
    @@visibility_timeouts = {}

    class << self
      def queues(queue)
        @@queues[queue.to_s] ||= sqs.queues.named(queue)
      end

      def visibility_timeout(queue)
        @@visibility_timeouts[queue.to_s] ||= queues(queue).visibility_timeout
      end

      def receive_message(queue, options = {})
        queues(queue).receive_message(Hash(options))
      end

      def send_message(queue, body, options = {})
        body = JSON.dump(body) if body.is_a?(Hash)

        queues(queue).send_message(body, options)
      end

      def sqs
        @sqs ||= AWS::SQS.new
      end
    end
  end
end
