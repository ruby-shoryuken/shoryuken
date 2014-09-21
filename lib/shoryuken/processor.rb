require 'multi_json'

module Shoryuken
  class Processor
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def process(queue, sqs_msg)
      if worker_class = Shoryuken.workers[queue]
        defer do
          worker = worker_class.new

          Shoryuken.server_middleware.invoke(worker, queue, sqs_msg) do
            worker.perform(sqs_msg)
          end
        end
      else
        logger.error "Worker not found for queue '#{queue}'"
      end

      @manager.async.processor_done(queue, current_actor)
    end

    def self.default_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Logging
        m.add Middleware::Server::AutoDelete
        # m.add Middleware::Server::RetryJobs
      end
    end
  end
end
