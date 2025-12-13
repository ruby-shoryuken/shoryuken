# frozen_string_literal: true

module Shoryuken
  # Default implementation of the worker registry.
  # Stores and retrieves worker classes mapped to queue names.
  class DefaultWorkerRegistry < WorkerRegistry
    # Initializes a new DefaultWorkerRegistry with an empty workers hash
    def initialize
      @workers = Shoryuken::Helpers::AtomicHash.new
    end

    # Checks if a queue is configured for batch message receiving
    #
    # @param queue [String] the queue name
    # @return [Boolean] true if the queue's worker has batch mode enabled
    def batch_receive_messages?(queue)
      !!(@workers[queue] && @workers[queue].get_shoryuken_options['batch'])
    end

    # Clears all registered workers
    #
    # @return [void]
    def clear
      @workers.clear
    end

    # Fetches a worker instance for processing a message
    #
    # @param queue [String] the queue name
    # @param message [Shoryuken::Message, Array<Shoryuken::Message>] the message or batch
    # @return [Object, nil] a new worker instance or nil if not found
    def fetch_worker(queue, message)
      worker_class = !message.is_a?(Array) &&
                     message.message_attributes &&
                     message.message_attributes['shoryuken_class'] &&
                     message.message_attributes['shoryuken_class'][:string_value]

      worker_class = begin
        Shoryuken::Helpers::StringUtils.constantize(worker_class)
      rescue
        @workers[queue]
      end

      worker_class.new if worker_class
    end

    # Returns all registered queue names
    #
    # @return [Array<String>] the queue names with registered workers
    def queues
      @workers.keys
    end

    # Registers a worker class for a queue
    #
    # @param queue [String] the queue name
    # @param clazz [Class] the worker class to register
    # @return [Class] the registered worker class
    # @raise [Errors::InvalidWorkerRegistrationError] if a batchable worker is already registered for the queue
    def register_worker(queue, clazz)
      if (worker_class = @workers[queue]) && (worker_class.get_shoryuken_options['batch'] == true || clazz.get_shoryuken_options['batch'] == true)
        raise Errors::InvalidWorkerRegistrationError, "Could not register #{clazz} for #{queue}, "\
          "because #{worker_class} is already registered for this queue, "\
          "and Shoryuken doesn't support a batchable worker for a queue with multiple workers"
      end

      @workers[queue] = clazz
    end

    # Returns all worker classes for a queue
    #
    # @param queue [String] the queue name
    # @return [Array<Class>] the registered worker classes
    def workers(queue)
      [@workers.fetch(queue, [])].flatten
    end
  end
end
