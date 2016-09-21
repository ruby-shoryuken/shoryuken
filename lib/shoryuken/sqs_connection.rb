module Shoryuken
  class SQSConnection
    def initialize(hash)
      # aws-sdk tries to load the credentials from the ENV variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
      # when not explicit supplied
      return if hash.empty?

      shoryuken_keys = %w(
        account_id
        sns_endpoint
        sqs_endpoint
        receive_message).map(&:to_sym)

      aws_options = hash.reject do |k, v|
        shoryuken_keys.include?(k)
      end

      # assume credentials based authentication
      credentials = Aws::Credentials.new(
        aws_options.delete(:access_key_id),
        aws_options.delete(:secret_access_key))

      # but only if the configuration options have valid values
      aws_options = aws_options.merge(credentials: credentials) if credentials.set?

      if (callback = Shoryuken.aws_initialization_callback)
        Shoryuken.logger.info { 'Calling Shoryuken.on_aws_initialization block' }
        callback.call(aws_options)
      end

      Aws.config = aws_options
    end
  end
end

