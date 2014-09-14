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
          worker_class.new.perform(sqs_msg)
          sqs_msg.delete if worker_class.get_shoryuken_options['auto_delete']
        end
      else
        logger.error "Worker not found for queue '#{queue}'"
      end

      @manager.async.processor_done(queue, current_actor)
    end
  end
end
