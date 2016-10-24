module Shoryuken
  class Client
    @@queues = {}
    @@topics = {}

    class << self
      def queues(name)
        @@queues[name.to_s] ||= Shoryuken::Queue.new(sqs, name)
      end

      def sns
        @sns ||= Shoryuken::AwsConfig.sns
      end

      def sns_arn
        @sns_arn ||= SnsArn
      end

      def sqs
        @sqs ||= Shoryuken::AwsConfig.sqs
      end

      def topics(name)
        @@topics[name.to_s] ||= Topic.new(name, sns)
      end

      attr_accessor :account_id
      attr_writer :sns, :sqs, :sqs_resource, :sns_arn
    end
  end
end
