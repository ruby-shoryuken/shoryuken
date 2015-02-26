module Shoryuken
  class SnsArn
    def initialize topic
      @topic = topic
    end

    def to_s
      @arn ||= "arn:aws:sns:#{region}:#{account_id}:#{@topic}"
    end

    private

    def account_id
      Shoryuken::Client.account_id.tap do |account_id|
        if account_id.to_s.empty?
          fail "To generate SNS ARNs, you must assign an :account_id in your Shoryuken::Client."
        end
      end
    end

    def region
      Aws.config.fetch(:region) do
        fail "To generate SNS ARNs, you must include a :region in your AWS config."
      end
    end
  end
end
