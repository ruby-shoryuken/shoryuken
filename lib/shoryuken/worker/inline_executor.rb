module Shoryuken
  module Worker
    class InlineExecutor
      class << self
        def perform_async(worker_class, body, options = {})
          body = JSON.dump(body) if body.is_a?(Hash)

          sqs_msg = OpenStruct.new(body: body)

          new.perform(sqs_msg, BodyParser.parse(self, sqs_msg))
        end

        def perform_in(worker_class, interval, body, options = {})
          perform_async(body, options)
        end
      end
    end
  end
end
