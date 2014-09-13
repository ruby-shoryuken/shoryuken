
module Shoryuken
  class Client
    @@queues = {}

    def self.queue_by_name(name)
      @@queues[name.to_s] ||= sqs.queues.named(name)
    end

    def self.receive_message(queue, options = {})
      queue.receive_message(options)
    end

    def self.sqs
      @sqs ||= AWS::SQS.new
    end
  end
end
