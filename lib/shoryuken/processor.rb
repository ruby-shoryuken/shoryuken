require 'multi_json'

module Shoryuken
  class Processor
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def process(queue, sqs_msg, payload)
      klass  = constantize(payload['class'])
      worker = klass.new

      defer do
        worker.perform(sqs_msg, *payload['args'])
      end

      @manager.async.processor_done(current_actor)
    end
  end
end
