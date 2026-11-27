# frozen_string_literal: true

module Shoryuken
  module Worker
    # Resolves the queue an executor uses when perform_async gets no :queue option.
    # Extended by the executors so the inline executor raises the same errors as production.
    # @api private
    module DefaultQueue
      private

      # Returns the queue to send to when no :queue option is given
      #
      # @param worker_class [Class] the worker class
      # @return [String] the worker's queue
      # @raise [Errors::QueueNotSpecifiedError] if the worker has no queue or several queues
      def default_queue(worker_class)
        queue = worker_class.get_shoryuken_options['queue']

        return queue unless queue.is_a?(Array)
        return queue.first if queue.size == 1

        raise(Errors::QueueNotSpecifiedError, "#{worker_class} has no queue: pass the queue: option") if queue.empty?

        raise(
          Errors::QueueNotSpecifiedError,
          "#{worker_class} has several queues (#{queue.join(', ')}): pass the queue: option to choose one"
        )
      end
    end
  end
end
