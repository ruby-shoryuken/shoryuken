module Shoryuken
  class Client
    @@queues = {}

    class << self
      def queues(name)
        @@queues[name.to_s] ||= Shoryuken::Queue.new(sqs, name)
      end

      def sqs
        @@sqs ||= Shoryuken.sqs_client
      end

      def sqs=(sqs)
        @@sqs = sqs
      end
    end
  end
end
