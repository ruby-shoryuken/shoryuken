# frozen_string_literal: true

module Shoryuken
  # Utility methods shared across Shoryuken classes.
  # Provides logging, event firing, and helper methods.
  module Util
    # Returns the Shoryuken logger
    #
    # @return [Logger] the configured logger
    def logger
      Shoryuken.logger
    end

    # Fires a lifecycle event to all registered handlers
    #
    # @param event [Symbol] the event name to fire
    # @param reverse [Boolean] whether to call handlers in reverse order
    # @param event_options [Hash] options to pass to event handlers
    # @return [void]
    def fire_event(event, reverse = false, event_options = {})
      logger.debug { "Firing '#{event}' lifecycle event" }
      arr = Shoryuken.options[:lifecycle_events][event]
      arr.reverse! if reverse
      arr.each do |block|
        block.call(event_options)
      rescue => e
        logger.warn(event: event)
        logger.warn "#{e.class.name}: #{e.message}"
      end
    end

    # Calculates elapsed time in milliseconds
    #
    # @param started_at [Time] the start time
    # @return [Float] elapsed time in milliseconds
    def elapsed(started_at)
      # elapsed in ms
      (Time.now - started_at) * 1000
    end

    # Converts a queue array to a hash of queue names and weights
    #
    # @param queues [Array<String>] array of queue names with possible duplicates
    # @return [Array<Array>] array of [queue_name, weight] pairs
    def unparse_queues(queues)
      queues.each_with_object({}) do |name, queue_and_weights|
        queue_and_weights[name] = queue_and_weights[name].to_i + 1
      end.to_a
    end

    # Returns a display name for the worker processing a message
    #
    # @param worker_class [Class] the worker class
    # @param sqs_msg [Aws::SQS::Types::Message, Array] the message or batch
    # @param body [Object, nil] the parsed message body
    # @return [String] the worker display name
    def worker_name(worker_class, sqs_msg, body = nil)
      if Shoryuken.active_job? \
          && !sqs_msg.is_a?(Array) \
          && sqs_msg.message_attributes \
          && sqs_msg.message_attributes['shoryuken_class'] \
          && sqs_msg.message_attributes['shoryuken_class'][:string_value] \
          == 'Shoryuken::ActiveJob::JobWrapper' \
          && body

        "ActiveJob/#{body['job_class']}"
      else
        worker_class.to_s
      end
    end
  end
end
