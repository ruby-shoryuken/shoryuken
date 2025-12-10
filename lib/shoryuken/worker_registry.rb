# frozen_string_literal: true

module Shoryuken
  # Abstract base class for worker registries.
  # Defines the interface for storing and retrieving worker classes.
  # @abstract Subclass and implement all methods to create a custom registry
  class WorkerRegistry
    # Checks if the workers for a queue support batch message processing
    #
    # @param _queue [String] the queue name
    # @return [Boolean] true if batch processing is supported
    # @raise [NotImplementedError] if not implemented by subclass
    def batch_receive_messages?(_queue)
      # true if the workers for queue support batch processing of messages
      fail NotImplementedError
    end

    # Removes all worker registrations
    #
    # @return [void]
    # @raise [NotImplementedError] if not implemented by subclass
    def clear
      # must remove all worker registrations
      fail NotImplementedError
    end

    # Fetches a worker instance for processing a message
    #
    # @param _queue [String] the queue name
    # @param _message [Shoryuken::Message, Array<Shoryuken::Message>] the message or batch
    # @return [Object] a worker instance
    # @raise [NotImplementedError] if not implemented by subclass
    def fetch_worker(_queue, _message)
      # must return an instance of the worker that handles
      # message received on queue
      fail NotImplementedError
    end

    # Returns a list of all queues with registered workers
    #
    # @return [Array<String>] the queue names
    # @raise [NotImplementedError] if not implemented by subclass
    def queues
      # must return a list of all queues with registered workers
      fail NotImplementedError
    end

    # Registers a worker class for a queue
    #
    # @param _queue [String] the queue name
    # @param _clazz [Class] the worker class
    # @return [void]
    # @raise [NotImplementedError] if not implemented by subclass
    def register_worker(_queue, _clazz)
      # must register the worker as a consumer of messages from queue
      fail NotImplementedError
    end

    # Returns all worker classes registered for a queue
    #
    # @param _queue [String] the queue name
    # @return [Array<Class>] the worker classes, or empty array
    # @raise [NotImplementedError] if not implemented by subclass
    def workers(_queue)
      # must return the list of workers registered for queue, or []
      fail NotImplementedError
    end
  end
end
