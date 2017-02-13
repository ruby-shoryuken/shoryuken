module Shoryuken
  module Middleware
    module Server
      class AutoExtendVisibility
        include Util

        EXTEND_UPFRONT_SECONDS = 5

        def call(worker, queue, sqs_msg, body)
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

        class MessageVisibilityExtender
          include Util

          def auto_extend(worker, queue, sqs_msg, body)
            queue_visibility_timeout = Shoryuken::Client.queues(queue).visibility_timeout

            Concurrent::TimerTask.new(execution_interval: queue_visibility_timeout - EXTEND_UPFRONT_SECONDS) do
              begin
                logger.debug do
                  "Extending message #{worker_name(worker.class, sqs_msg, body)}/#{queue}/#{sqs_msg.message_id} " \
                  "visibility timeout by #{queue_visibility_timeout}s."
                end

                sqs_msg.change_visibility(visibility_timeout: queue_visibility_timeout)
              rescue => e
                logger.error do
                  'Could not auto extend the message ' \
                  "#{worker_name(worker.class, sqs_msg, body)}/#{queue}/#{sqs_msg.message_id} " \
                  "visibility timeout. Error: #{e.message}"
                end
              end
            end
          end
        end

        def auto_visibility_timer(worker, queue, sqs_msg, body)
          return unless worker.class.auto_visibility_timeout?

          MessageVisibilityExtender.new.auto_extend(worker, queue, sqs_msg, body).tap(&:execute)
        end
      end
    end
  end
end
