module Shoryuken
  module Middleware
    module Server
      class AutoDelete

        def call(worker, queue, sqs_msg, body)
          yield

          delete = worker.class.get_shoryuken_options['delete'] || worker.class.get_shoryuken_options['auto_delete']

          Array(sqs_msg).each(&:delete) if delete
        end
      end
    end
  end
end

