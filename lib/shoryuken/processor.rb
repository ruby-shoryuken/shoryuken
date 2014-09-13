require 'multi_json'

module Shoryuken
  class Processor
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def process(queue, sqs_msg)
      if worker_class = Shoryuken.workers[queue.arn.split(':').last]
        defer do
          worker_class.new.perform(sqs_msg)
          sqs_msg.delete if worker_class.get_shoryuken_options['auto_delete']
        end
      else
        Shoryuken.logger.error "Worker not found for queue '#{queue.arn}'"
      end

      @manager.async.processor_done(current_actor)
    end
  end
end
