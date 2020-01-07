module Shoryuken
  module Middleware
    module Server
      class Timing
        include Util

        def call(_worker, _queue, sqs_msg, _body)
          started_at = Time.now

          logger.info { "started at #{started_at}" }

          yield

          ended_at = Time.now
          total_time = (ended_at - started_at) * 1000

          if ended_at > sqs_msg.become_available_at
            log_msg = 'exceeded the message visibility timeout by ' \
              "#{(ended_at - sqs_msg.become_available_at) * 1000} ms"
            logger.warn { log_msg }
          end

          logger.info { "completed in: #{total_time} ms" }
        rescue
          logger.info { "failed in: #{elapsed(started_at)} ms" }
          raise
        end
      end
    end
  end
end
