# frozen_string_literal: true

module Shoryuken
  # Client class for interacting with SQS queues.
  # Provides a simple interface for accessing and managing queue instances.
  class Client
    # @return [Hash{String => Shoryuken::Queue}] cached queue instances by name
    @@queues = {}

    # Guards the queue cache. queues is called concurrently from the dispatch
    # thread, processor-completion threads and worker threads, and building a
    # Shoryuken::Queue makes SQS API calls, so an unsynchronized `||=` would let
    # several callers build the same queue (and corrupt the hash on JRuby).
    @@queues_mutex = Mutex.new

    class << self
      # Returns a Queue instance for the given queue name
      #
      # @param name [String, Symbol] the name of the queue
      # @return [Shoryuken::Queue] the queue instance
      def queues(name)
        @@queues_mutex.synchronize { @@queues[name.to_s] ||= Shoryuken::Queue.new(sqs, name) }
      end

      # Returns the current SQS client
      #
      # @return [Aws::SQS::Client] the SQS client
      def sqs
        Shoryuken.sqs_client
      end

      # Sets a new SQS client and clears the queue cache
      #
      # @param sqs [Aws::SQS::Client] the new SQS client
      # @return [Aws::SQS::Client] the SQS client
      def sqs=(sqs)
        # Since the @@queues values (Shoryuken::Queue objects) are built referencing @@sqs, if it changes, we need to
        #   re-build them on subsequent calls to `.queues(name)`.
        @@queues_mutex.synchronize { @@queues = {} }

        Shoryuken.sqs_client = sqs
      end
    end
  end
end
