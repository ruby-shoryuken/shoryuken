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

            Shoryuken::Helpers::TimerTask.new(execution_interval: queue_visibility_timeout - EXTEND_UPFRONT_SECONDS) do
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
        end

        # Creates and starts a visibility extension timer
        #
        # @param worker [Object] the worker instance
        # @param queue [String] the queue name
        # @param sqs_msg [Shoryuken::Message] the message
        # @param body [Object] the parsed message body
        # @return [Shoryuken::Helpers::TimerTask] the started timer
        def auto_visibility_timer(worker, queue, sqs_msg, body)
          MessageVisibilityExtender.new.auto_extend(worker, queue, sqs_msg, body).tap(&:execute)
        end
      end
    end
  end
end
