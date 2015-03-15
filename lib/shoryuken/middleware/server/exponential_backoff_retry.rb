module Shoryuken
  module Middleware
    module Server
      class ExponentialBackoffRetry
        include Util

        def call(worker, queue, sqs_msg, body)
          started_at = Time.now
          yield
        rescue
          retry_intervals = Array(worker.class.get_shoryuken_options['retry_intervals'])

          if retry_intervals.empty? || !handle_failure(sqs_msg, started_at, retry_intervals)
            # Re-raise the exception if the job is not going to be exponential backoff retried.
            # This allows custom middleware (like exception notifiers) to be aware of the unhandled failure.
            raise
          end
        end

        private

        def handle_failure(sqs_msg, started_at, retry_intervals)
          attempts = sqs_msg.attributes['ApproximateReceiveCount']

          return unless attempts

          attempts = attempts.to_i - 1

          interval = if attempts < retry_intervals.size
                       retry_intervals[attempts]
                     else
                       retry_intervals.last
                     end

          # Visibility timeouts are limited to a total 12 hours, starting from the receipt of the message.
          # We calculate the maximum timeout by subtracting the amount of time since the receipt of the message.
          #
          # From the docs:  "Amazon SQS restarts the timeout period using the new value."
          # http://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/AboutVT.html#AboutVT-extending-message-visibility-timeout
          max_timeout = 43200 - (Time.now - started_at).ceil - 1
          interval = max_timeout if interval > max_timeout

          sqs_msg.change_visibility(visibility_timeout: interval.to_i)

          logger.info "Message #{sqs_msg.message_id} failed, will be retried in #{interval} seconds."
        end
      end
    end
  end
end
