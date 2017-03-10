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

          if attempts <= (retry_intervals = Array(retry_intervals)).size
            retry_intervals[attempts - 1]
          else
            retry_intervals.last
          end
        end

        def next_visibility_timeout(interval, started_at)
          max_timeout = 43_200 - (Time.now - started_at).ceil - 1
          interval = max_timeout if interval > max_timeout
          interval.to_i
        end

        def handle_failure(sqs_msg, started_at, retry_intervals)
          receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i

          return false unless (interval = get_interval(retry_intervals, receive_count))

          sqs_msg.change_visibility(visibility_timeout: next_visibility_timeout(interval.to_i, started_at))

          logger.info { "Message #{sqs_msg.message_id} failed, will be retried in #{interval} seconds." }

          true
        end
      end
    end
  end
end
