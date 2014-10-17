module Shoryuken
  module Middleware
    module Server
      class AutoDelete
        def call(worker, queue, sqs_msg)
          yield

          Array(sqs_msg).each(&:delete) if worker.class.get_shoryuken_options['auto_delete']
        end
      end
    end
  end
end

