# frozen_string_literal: true

module Shoryuken
  module Middleware
    module Server
      # Middleware that automatically extends message visibility timeout during processing.
      # Prevents messages from becoming visible to other consumers while still being processed.
      class AutoExtendVisibility
        include Util

        # Number of seconds before timeout to extend visibility
        EXTEND_UPFRONT_SECONDS = 5

        # Processes a message with automatic visibility timeout extension
        #
        # @param worker [Object] the worker instance
        # @param queue [String] the queue name
        # @param sqs_msg [Shoryuken::Message, Array<Shoryuken::Message>] the message or batch
        # @param body [Object] the parsed message body
        # @yield continues to the next middleware in the chain
        # @return [void]
        def call(worker, queue, sqs_msg, body)
          return yield unless worker.class.auto_visibility_timeout?

          if sqs_msg.is_a?(Array)
            logger.warn { "Auto extend visibility isn't supported for batch workers" }
            return yield
          end

          timer = auto_visibility_timer(worker, queue, sqs_msg, body)
          yield
        ensure
          timer.kill if timer
        end

        private

        # Helper class for extending message visibility
        class MessageVisibilityExtender
          include Util

          # Creates a timer task that extends message visibility
          #
          # @param _worker [Object] the worker instance (unused)
          # @param queue [String] the queue name
          # @param sqs_msg [Shoryuken::Message] the message
          # @param _body [Object] the parsed message body (unused)
          # @return [Shoryuken::Helpers::TimerTask] the timer task
          def auto_extend(_worker, queue, sqs_msg, _body)
            queue_visibility_timeout = Shoryuken::Client.queues(queue).visibility_timeout
            execution_interval = extension_interval(queue_visibility_timeout)

            unless execution_interval
              logger.warn do
                "Not auto-extending visibility for #{queue}/#{sqs_msg.message_id}: queue visibility " \
                "timeout (#{queue_visibility_timeout}s) is too short. Increase it to use auto_visibility_timeout."
              end
              return nil
            end

            Shoryuken::Helpers::TimerTask.new(execution_interval: execution_interval) do
              logger.debug do
                "Extending message #{queue}/#{sqs_msg.message_id} visibility timeout by #{queue_visibility_timeout}s"
              end

              sqs_msg.change_visibility(visibility_timeout: queue_visibility_timeout)
            rescue => e
              logger.error do
                "Could not auto extend the message #{queue}/#{sqs_msg.message_id} visibility timeout. Error: #{e.message}"
              end
            end
          end

          private

          # Returns a positive interval at which to re-extend the message's
          # visibility before it expires, or nil when the visibility timeout is
          # too short to schedule one. Normally this is EXTEND_UPFRONT_SECONDS
          # before expiry, but for short timeouts (<= EXTEND_UPFRONT_SECONDS) it
          # falls back to half the timeout so the timer still fires in time
          # instead of TimerTask raising on a non-positive interval.
          #
          # @param visibility_timeout [Integer] the queue's visibility timeout in seconds
          # @return [Float, Integer, nil] the execution interval, or nil if too short
          def extension_interval(visibility_timeout)
            return nil if visibility_timeout <= 0

            interval = visibility_timeout - EXTEND_UPFRONT_SECONDS
            interval = visibility_timeout / 2.0 if interval <= 0
            interval
          end
        end

        # Creates and starts a visibility extension timer
        #
        # @param worker [Object] the worker instance
        # @param queue [String] the queue name
        # @param sqs_msg [Shoryuken::Message] the message
        # @param body [Object] the parsed message body
        # @return [Shoryuken::Helpers::TimerTask] the started timer
        def auto_visibility_timer(worker, queue, sqs_msg, body)
          timer = MessageVisibilityExtender.new.auto_extend(worker, queue, sqs_msg, body)
          timer&.execute
          timer
        end
      end
    end
  end
end
