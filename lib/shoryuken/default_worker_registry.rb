# frozen_string_literal: true

module Shoryuken
  class DefaultWorkerRegistry < WorkerRegistry
    def initialize
      @workers = Concurrent::Hash.new
    end

    def batch_receive_messages?(queue)
      !!(@workers[queue] && @workers[queue].get_shoryuken_options['batch'])
    end

    def clear
      @workers.clear
    end

    def fetch_worker(queue, message)
      worker_class = !message.is_a?(Array) &&
                     message.message_attributes &&
                     message.message_attributes['shoryuken_class'] &&
                     message.message_attributes['shoryuken_class'][:string_value]

      worker_class = begin
                       worker_class.constantize
                     rescue
                       @workers[queue]
                     end

      worker_class.new if worker_class
    end

    def queues
      @workers.keys
    end

    def register_worker(queue, clazz)
      if (worker_class = @workers[queue])
        if worker_class.get_shoryuken_options['batch'] == true || clazz.get_shoryuken_options['batch'] == true
          fail ArgumentError, "Could not register #{clazz} for #{queue}, "\
            "because #{worker_class} is already registered for this queue, "\
            "and Shoryuken doesn't support a batchable worker for a queue with multiple workers"
        end
      end

      @workers[queue] = clazz
    end

    def workers(queue)
      [@workers.fetch(queue, [])].flatten
    end
  end
end
