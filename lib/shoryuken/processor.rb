require 'multi_json'

module Shoryuken
  class Processor
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def process(queue, sqs_msg, payload)
      klass  = payload['class'].constantize
      worker = klass.new

      defer do
        worker.perform(sqs_msg, *payload['args'])
      end

      @manager.async.processor_done(current_actor)
    rescue
      sqs_msg.delete
    end
  end
end
