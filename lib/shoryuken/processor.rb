module Shoryuken
  class Processor
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def process(queue, sqs_msg)
      HelloWorker.new.perform(sqs_msg)

      @manager.processor_done(current_actor)
    end
  end
end
