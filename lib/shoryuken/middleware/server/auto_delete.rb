module Shoryuken
  module Middleware
    module Server
      class AutoDelete
        def call(worker, queue, sqs_msg, body)
          yield

          auto_delete = worker.class.get_shoryuken_options['delete'] || worker.class.get_shoryuken_options['auto_delete']

          Shoryuken::Client.queues(queue).batch_delete(*Array(sqs_msg)) if auto_delete
        end
      end
    end
  end
end

