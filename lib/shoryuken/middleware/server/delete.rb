module Shoryuken
  module Middleware
    module Server
      class Delete
        def call(worker, queue, sqs_msg)
          yield

          # auto_delete is deprecated
          delete = worker.class.get_shoryuken_options['delete'] || worker.class.get_shoryuken_options['auto_delete']

          Array(sqs_msg).each(&:delete) if delete
        end
      end
    end
  end
end

