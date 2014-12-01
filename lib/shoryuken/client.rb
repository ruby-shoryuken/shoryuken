module Shoryuken
  class Client
    @@queues = {}

    class << self
      def queues(name)
        @@queues[name.to_s] ||= Queue.new(name, sqs)
      end

      def sqs
        @sqs ||= Aws::SQS::Client.new
      end

      attr_writer :sqs
    end
  end
end
