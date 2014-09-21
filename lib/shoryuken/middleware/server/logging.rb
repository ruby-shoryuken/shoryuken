module Shoryuken
  module Middleware
    module Server
      class Logging
        include Util

        def call(worker, queue, sqs_msg)
          Shoryuken::Logging.with_context("#{worker.class.to_s} '#{queue}' '#{sqs_msg.id}'") do
            begin
              started_at = Time.now
              logger.info { "started at #{started_at}" }
              yield
              logger.info { "completed in: #{elapsed(started_at)} ms" }
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
