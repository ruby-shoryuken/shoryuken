module Shoryuken
  class Processor
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def process(queue, sqs_msg)
      worker_class = Shoryuken.workers[queue]
      defer do
        worker = worker_class.new

        Shoryuken.server_middleware.invoke(worker, queue, sqs_msg) do
          worker.perform(sqs_msg)
        end
      end

      @manager.async.processor_done(queue, current_actor)
    end
  end
end
