module Shoryuken
  module Middleware
    module Server
      class Timing
        include Util

        def call(worker, queue, sqs_msg, body)
          class_name = if defined?(::ActiveJob) \
                        && !sqs_msg.is_a?(Array) \
                        && sqs_msg.message_attributes['shoryuken_class'] \
                        && sqs_msg.message_attributes['shoryuken_class'][:string_value] == ActiveJob::QueueAdapters::ShoryukenAdapter::JobWrapper.to_s
                         "ActiveJob/#{body['job_class'].constantize}"
                       else
                         worker.class.to_s
                       end
          Shoryuken::Logging.with_context("#{class_name}/#{queue}/#{sqs_msg.id}") do
            begin
              started_at = Time.now

              logger.info "started at #{started_at}"

              yield

              total_time = elapsed(started_at)

              if (total_time / 1000.0) > (timeout = Shoryuken::Client.visibility_timeout(queue))
                logger.warn "exceeded the queue visibility timeout by #{total_time - (timeout * 1000)} ms"
              end

              logger.info "completed in: #{total_time} ms"
            rescue => e
              logger.info "failed in: #{elapsed(started_at)} ms"
              raise e
            end
          end
        end
      end
    end
  end
end
