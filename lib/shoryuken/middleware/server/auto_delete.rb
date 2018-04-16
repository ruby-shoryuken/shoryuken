module Shoryuken
  module Middleware
    module Server
      class AutoDelete
        def call(worker, queue, sqs_msg, _body)
          yield

          return unless worker.class.auto_delete?

          entries = [sqs_msg].flatten.map.with_index { |message, i| { id: i.to_s, receipt_handle: message.receipt_handle } }

          Shoryuken::Client.queues(queue).delete_messages(entries: entries)
        end
      end
    end
  end
end
