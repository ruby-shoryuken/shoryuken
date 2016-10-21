module Shoryuken
  class Client
    @@queues = {}
    @@topics = {}

    class << self
      def queues(name)
        @@queues[name.to_s] ||= Shoryuken::Queue.new(sqs, name)
      end

      def sns
        @sns ||= Aws::SNS::Client.new(aws_client_options(:sns))
      end

      def sns_arn
        @sns_arn ||= SnsArn
      end

      def sqs
        @sqs ||= Aws::SQS::Client.new(aws_client_options(:sqs))
      end

      def topics(name)
        @@topics[name.to_s] ||= Topic.new(name, sns)
      end

      attr_accessor :account_id
      attr_writer :sns, :sqs, :sqs_resource, :sns_arn

      private

      def aws_client_options(client_type)
        service_endpoint_key = "#{client_type}_endpoint".to_sym
        environment_endpoint = ENV["AWS_#{service_endpoint_key.to_s.upcase}"]
        explicit_endpoint = Shoryuken.options[:aws][service_endpoint_key] || environment_endpoint
        options = Shoryuken.options[client_type] || {}
        options[:endpoint] = explicit_endpoint unless explicit_endpoint.to_s.empty?
        options
      end
    end
  end
end
