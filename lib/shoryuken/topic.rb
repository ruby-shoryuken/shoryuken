module Shoryuken
  class Topic
    def initialize(name, sns)
      @name, @sns = name, sns
    end

    def arn
      @arn ||= Client.sns_arn.new(@name).to_s
    end

    def send_message(body, options = {})
      body = JSON.dump(body) if body.is_a?(Hash)

      @sns.publish(topic_arn: arn, message: body)
    end
  end
end
