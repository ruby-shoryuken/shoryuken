module Shoryuken
  module Middleware
    module Server
      class AutoExtendVisibility
        EXTEND_UPFRONT_SECONDS = 5

        def call(worker, queue, sqs_msg, body)
          timer = auto_visibility_timer(worker, queue, sqs_msg, body)
          begin
            yield
          ensure
            if timer
              timer.shutdown
              @visibility_extender.ask!(:terminate)
            end
          end
        end

        private

        class MessageVisibilityExtender < Concurrent::Actor::RestartingContext
          include Util

          def auto_extend(worker, queue, sqs_msg, body)
            queue_visibility_timeout = Shoryuken::Client.queues(queue).visibility_timeout

            interval = queue_visibility_timeout - EXTEND_UPFRONT_SECONDS

            Concurrent::TimerTask.execute(execution_interval: interval, timeout_interval: interval) do
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
          @visibility_extender = MessageVisibilityExtender.spawn! name: :message_visibility_extender, link: true
          @visibility_extender.auto_extend(worker, queue, sqs_msg, body)
        end
      end
    end
  end
end
