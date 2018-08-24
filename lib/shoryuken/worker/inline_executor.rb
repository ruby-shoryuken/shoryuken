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

          parsed_body = BodyParser.parse(worker_class, sqs_msg)
          batch = worker_class.shoryuken_options_hash['batch']
          arg0, arg1 = format_args(sqs_msg, body, batch)
          worker_class.new.perform(arg0, arg1)
        end

        def perform_in(worker_class, _interval, body, options = {})
          perform_async(worker_class, body, options)
        end

      private

        def format_args(sqs_msg, parsed_body, batch)
          batch ? [[sqs_msg], [parsed_body]] : [sqs_msg, parsed_body]
        end
      end
    end
  end
end
