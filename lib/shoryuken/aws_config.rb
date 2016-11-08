# frozen_string_literal: true
module Shoryuken
  class AwsConfig
    class << self
      attr_writer :options

      def options
        @options ||= {}
      end

      def setup(hash)
        # aws-sdk tries to load the credentials from the ENV variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
        # when not explicit supplied
        return if hash.empty?

        self.options = hash

        shoryuken_keys = %w(
          account_id
          sns_endpoint
          sqs_endpoint
          receive_message
        ).map(&:to_sym)

        @aws_options = hash.reject do |k, _|
          shoryuken_keys.include?(k)
        end

        # assume credentials based authentication
        credentials = Aws::Credentials.new(
          @aws_options.delete(:access_key_id),
          @aws_options.delete(:secret_access_key)
        )

        # but only if the configuration options have valid values
        @aws_options.merge!(credentials: credentials) if credentials.set?

        if (callback = Shoryuken.aws_initialization_callback)
          Shoryuken.logger.info { 'Calling Shoryuken.on_aws_initialization block' }
          callback.call(@aws_options)
        end
      end

      def sns
        Aws::SNS::Client.new(aws_client_options(:sns_endpoint))
      end

      def sqs
        Aws::SQS::Client.new(aws_client_options(:sqs_endpoint))
      end

      private

      def aws_client_options(service_endpoint_key)
        environment_endpoint = ENV["AWS_#{service_endpoint_key.to_s.upcase}"]
        explicit_endpoint = options[service_endpoint_key] || environment_endpoint
        endpoint = {}.tap do |hash|
          hash[:endpoint] = explicit_endpoint unless explicit_endpoint.to_s.empty?
        end
        @aws_options.to_h.merge(endpoint)
      end
    end
  end
end
