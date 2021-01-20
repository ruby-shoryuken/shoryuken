module Shoryuken
  module Middleware
    module Server
      class Timing
        include Util

        def call(_worker, queue, _sqs_msg, _body)
          started_at = Time.now

          logger.info { "started at #{started_at}" }

          yield

          total_time = elapsed(started_at)

          if (total_time / 1000.0) > (timeout = Shoryuken::Client.queues(queue).visibility_timeout)
            logger.warn { "exceeded the queue visibility timeout by #{total_time - (timeout * 1000)} ms" }
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
