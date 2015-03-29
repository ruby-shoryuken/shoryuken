module Shoryuken
  class Client
    @@queues = {}
    @@topics = {}

    class << self
      def queues(name)
        @@queues[name.to_s] ||= Shoryuken::Queue.new(sqs, name)
      end

      def sns
        @sns ||= Aws::SNS::Client.new(aws_client_options(:sns_endpoint))
      end

      def sns_arn
        @sns_arn ||= SnsArn
      end

      def sqs
        @sqs ||= Aws::SQS::Client.new(aws_client_options(:sqs_endpoint))
      end

      def topics(name)
        @@topics[name.to_s] ||= Topic.new(name, sns)
      end

      attr_accessor :account_id
      attr_writer :sns, :sqs, :sqs_resource, :sns_arn

      private

      def aws_client_options(service_endpoint_key)
        explicit_endpoint = Shoryuken.options[:aws][service_endpoint_key]
        options = {}
        options[:endpoint] = explicit_endpoint unless explicit_endpoint.to_s.empty?
        options
      end
    end
  end
end
