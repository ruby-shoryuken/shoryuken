module Shoryuken
  module Middleware
    module Server
      class AutoDelete
        MAX_BATCH_SIZE = 10

        def call(worker, queue, sqs_msg, _body)
          yield

          return unless worker.class.auto_delete?

          [sqs_msg].flatten.in_groups_of(MAX_BATCH_SIZE, false).each do |sqs_msgs|
            entries = sqs_msgs.map.with_index { |message, i| { id: i.to_s, receipt_handle: message.receipt_handle } }

            Shoryuken::Client.queues(queue).delete_messages(entries: entries)
          end
        end
      end
    end
  end
end
