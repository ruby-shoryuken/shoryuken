module Shoryuken
  module Worker
    class InlineExecutor
      class << self
        def perform_async(worker_class, body, _options = {})
          body = JSON.dump(body) if body.is_a?(Hash)

          sqs_msg = OpenStruct.new(
            body: body,
            attributes: nil,
            md5_of_body: nil,
            md5_of_message_attributes: nil,
            message_attributes: nil,
            message_id: nil,
            receipt_handle: nil,
            delete: nil
          )

          call(worker_class, sqs_msg)
        end

        def perform_in(worker_class, _interval, body, options = {})
          worker_class.perform_async(body, options)
        end

        private

        def call(worker_class, sqs_msg)
          parsed_body = BodyParser.parse(worker_class, sqs_msg)
          batch = worker_class.shoryuken_options_hash['batch']
          args = batch ? [[sqs_msg], [parsed_body]] : [sqs_msg, parsed_body]
          worker_class.new.perform(*args)
        end
      end
    end
  end
end
