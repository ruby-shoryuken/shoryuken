module Shoryuken
  module Middleware
    module Server
      class AutoDelete
        def call(worker, queue, sqs_msg, body)
          yield

          auto_delete = worker.class.get_shoryuken_options['delete'] || worker.class.get_shoryuken_options['auto_delete']

          if auto_delete
            entries = [sqs_msg].flatten.map.with_index do |message, i|
              { id: i.to_s, receipt_handle: message.receipt_handle }
            end

            Shoryuken::Client.queues(queue).delete_messages(entries: entries)
          end
        end
      end
    end
  end
end

