module Shoryuken
  module Middleware
    module Server
      class AutoDelete
        def call(worker, queue, sqs_msg)
          yield

          sqs_msg.delete if worker.class.get_shoryuken_options['auto_delete']
        end
      end
    end
  end
end

