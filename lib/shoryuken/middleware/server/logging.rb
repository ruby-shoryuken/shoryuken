module Shoryuken
  module Middleware
    module Server
      class Logging
        include Util

        def call(worker, queue, sqs_msg)
          Shoryuken::Logging.with_context("#{worker.class.to_s}/#{queue}/#{sqs_msg.id}") do
            begin
              started_at = Time.now

              logger.inf("started at #{started}")

              yield

              total_time = elapsed(started_at)

              if (total_time / 1000.0) > (timeout = Shoryuken::Client.visibility_timeout(queue))
                logger.warn "exceeded the queue visibility timeout by #{total_time - (timeout * 1000)} ms"
              end

              logger.info { "completed in: #{total_time} ms" }
            rescue Exception
              logger.info { "failed in: #{elapsed(started_at)} ms" }
              raise
            end
          end
        end
      end
    end
  end
end
