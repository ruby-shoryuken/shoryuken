require 'celluloid' unless defined?(Celluloid)

module Shoryuken
  module Middleware
    module Server
      class AutoExtendVisibility
        EXTEND_UPFRONT_SECONDS = 5

        def call(worker, queue, sqs_msg, body)
          timer = auto_visibility_timer(queue, sqs_msg, worker.class)
          begin
            yield
          ensure
            timer.cancel if timer
          end
        end

        private

        class MessageVisibilityExtender
          include Celluloid
          include Util

          def auto_extend(queue, sqs_msg, worker_class)
            queue_visibility_timeout = Shoryuken::Client.queues(queue).visibility_timeout

            every(queue_visibility_timeout - EXTEND_UPFRONT_SECONDS) do
              begin
                logger.debug do
                  "Extending message #{worker_name(worker_class, sqs_msg)}/#{queue}/#{sqs_msg.message_id}  " \
                               "visibility timeout by #{queue_visibility_timeout}s."
                end

                sqs_msg.change_visibility(visibility_timeout: queue_visibility_timeout)
              rescue => e
                logger.error do
                  "Could not auto extend the message #{worker_class}/#{queue}/#{sqs_msg.message_id} " \
                               "visibility timeout. Error: #{e.message}"
                end
              end
            end
          end
        end

        def auto_visibility_timer(queue, sqs_msg, worker_class)
          return unless worker_class.auto_visibility_timeout?
          @visibility_extender ||= MessageVisibilityExtender.new_link
          @visibility_extender.auto_extend(queue, sqs_msg, worker_class)
        end
      end
    end
  end
end
