module Shoryuken
  module Middleware
    module Server
      class UnpauseQueue
        def call(_worker, queue, _sqs_msg, _body, strategy)
          yield
          client_queue = Shoryuken::Client.queues(queue)
          return unless client_queue.fifo?

          strategy.unpause_queue(queue)
        end
      end
    end
  end
end
