module Shoryuken
  class QueueRegistration
    def initialize worker
      @worker = worker
    end

    def register_queues! queues
      normalize_queues(queues).each do |queue|
        Shoryuken.register_worker queue, @worker
      end
    end

    private

    def normalize_queues queues
      Array(queues).map do |queue|
        queue.respond_to?(:call) ? queue.call : queue
      end
    end
  end
end
