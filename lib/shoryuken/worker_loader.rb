module Shoryuken
  class WorkerLoader
    class << self
      def call(queue, sqs_msg)
        # missing `try?` - yes, I'm
        worker_class = !sqs_msg.is_a?(Array) &&
          sqs_msg.message_attributes &&
          sqs_msg.message_attributes['shoryuken_class'] &&
          sqs_msg.message_attributes['shoryuken_class'][:string_value]

        worker_class = (worker_class.constantize rescue nil) || Shoryuken.workers[queue]

        worker_class.new
      end
    end
  end
end
