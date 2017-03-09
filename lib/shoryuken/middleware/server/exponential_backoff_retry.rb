module Shoryuken
  module Middleware
    module Server
      class ExponentialBackoffRetry
        include Util

        def call(worker, queue, sqs_msg, body)
          if sqs_msg.is_a?(Array)
            logger.warn { "Exponential backoff isn't supported for batch workers" }
            return yield
          end

          started_at = Time.now
          yield
        rescue
          retry_intervals = worker.class.get_shoryuken_options['retry_intervals']

          if retry_intervals.nil? || !handle_failure(sqs_msg, started_at, retry_intervals)
            # Re-raise the exception if the job is not going to be exponential backoff retried.
            # This allows custom middleware (like exception notifiers) to be aware of the unhandled failure.
            raise
          end
        end

        private

        def get_interval(retry_intervals, attempts)
          return retry_intervals.call(attempts) if retry_intervals.respond_to?(:call)

          if attempts < (retry_intervals = Array(retry_intervals)).size
            retry_intervals[attempts]
          else
            retry_intervals.last
          end
        end

        def get_attempts(sqs_msg)
          sqs_msg.attributes['ApproximateReceiveCount'].to_i - 1
        end

        def next_visibility_timeout(interval, started_at)
          max_timeout = 43_200 - (Time.now - started_at).ceil - 1
          interval = max_timeout if interval > max_timeout
          interval.to_i
        end

        def handle_failure(sqs_msg, started_at, retry_intervals)
          return false unless (attempts = get_attempts(sqs_msg))

          attempts = attempts.to_i - 1

          return false unless (interval = get_interval(retry_intervals, attempts))

          # Visibility timeouts are limited to a total 12 hours, starting from the receipt of the message.
          # We calculate the maximum timeout by subtracting the amount of time since the receipt of the message.
          #
          # From the docs:  "Amazon SQS restarts the timeout period using the new value."
          # http://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/AboutVT.html#AboutVT-extending-message-visibility-timeout
          sqs_msg.change_visibility(visibility_timeout: next_visibility_timeout(interval, started_at))

          logger.info { "Message #{sqs_msg.message_id} failed, will be retried in #{interval} seconds." }

          true
        end
      end
    end
  end
end
