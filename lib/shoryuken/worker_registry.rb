module Shoryuken
  class WorkerRegistry
    def batch_receive_messages?(queue)
      # true if the workers for queue support batch processing of messages
      fail NotImplementedError
    end

    def batch_by_interval(queue)
      # true if the workers for queue support batch processing of messages by a time interval
      fail NotImplementedError
    end

    def clear
      # must remove all worker registrations
      fail NotImplementedError
    end

    def fetch_worker(queue, message)
      # must return an instance of the worker that handles
      # message received on queue
      fail NotImplementedError
    end

    def queues
      # must return a list of all queues with registered workers
      fail NotImplementedError
    end

    def register_worker(queue, clazz)
      # must register the worker as a consumer of messages from queue
      fail NotImplementedError
    end

    def workers(queue)
      # must return the list of workers registered for queue, or []
      fail NotImplementedError
    end
  end
end
