
module Shoryuken
  class Client
    @@queues = {}

    def self.queues(name)
      @@queues[name.to_s] ||= sqs.queues.named(name)
    end

    def self.receive_message(queue, options = {})
      queues(queue).receive_message(Hash(options))
    end

    def self.reset!
      # for test purposes
      @@queues = {}
    end

    def self.sqs
      @sqs ||= AWS::SQS.new
    end
  end
end
