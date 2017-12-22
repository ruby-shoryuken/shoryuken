module Shoryuken
  module Worker
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def perform_async(body, options = {})
        body = JSON.dump(body) if body.is_a?(Hash)

        sqs_msg = OpenStruct.new(body: body)

        new.perform(sqs_msg, BodyParser.parse(self, sqs_msg))
      end

      def perform_in(interval, body, options = {})
        perform_async(body, options)
      end
    end
  end
end
