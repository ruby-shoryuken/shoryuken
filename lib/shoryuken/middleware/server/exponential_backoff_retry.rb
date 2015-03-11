module Shoryuken
  module Middleware
    module Server
      class ExponentialBackoffRetry
        include Util

        def call(worker, queue, sqs_msg, body)
          yield
        rescue Exception => e
          retry_intervals = Array(worker.class.get_shoryuken_options['retry_intervals'])
          if retry_intervals.empty?
            # Re-raise the exception if the job is not going to be retried.
            # This allows custom middleware (like exception notifiers) to be aware of the unhandled failure.
            raise e
          else
            handle_failure sqs_msg, retry_intervals
          end
        end
        
      private
      
        def handle_failure(sqs_msg, retry_intervals)
          attempts = sqs_msg.receive_count - 1
        
          interval = if attempts < retry_intervals.size
              retry_intervals[attempts]
            else
              retry_intervals.last
            end
        
          # Visibility timeouts are limited to 12 hours and are not additive.
          # From the docs:  "Amazon SQS restarts the timeout period using the new value."
          # http://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/AboutVT.html#AboutVT-extending-message-visibility-timeout
          interval = 43200 if interval > 43200
        
          sqs_msg.visibility_timeout = interval
        
          logger.info "Message #{sqs_msg.id} failed, will be retried in #{interval} seconds."
        end
      end
    end
  end
end
