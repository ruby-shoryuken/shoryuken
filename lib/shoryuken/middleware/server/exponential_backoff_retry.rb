# frozen_string_literal: true

module Shoryuken
  module Middleware
    module Server
      # Middleware that implements exponential backoff retry for failed messages.
      # When a job fails, the message visibility timeout is adjusted based on
      # configured retry intervals.
      class ExponentialBackoffRetry
        include Util

        # Processes a message with exponential backoff retry on failure
        #
        # @param worker [Object] the worker instance
        # @param _queue [String] the queue name (unused)
        # @param sqs_msg [Shoryuken::Message, Array<Shoryuken::Message>] the message or batch
        # @param _body [Object] the parsed message body (unused)
        # @yield continues to the next middleware in the chain
        # @return [void]
        # @raise [StandardError] re-raises the original exception if retry intervals are not configured
        #   or if retry limit is exceeded
        def call(worker, _queue, sqs_msg, _body)
          return yield unless worker.class.exponential_backoff?

          if sqs_msg.is_a?(Array)
            logger.warn { "Exponential backoff isn't supported for batch workers" }
            return yield
          end

          started_at = Time.now
          yield
        rescue => e
          retry_intervals = worker.class.get_shoryuken_options['retry_intervals']

          if retry_intervals.nil? || !handle_failure(sqs_msg, started_at, retry_intervals)
            # Re-raise the exception if the job is not going to be exponential backoff retried.
            # This allows custom middleware (like exception notifiers) to be aware of the unhandled failure.
            raise
          end

          logger.warn { "Message #{sqs_msg.message_id} will attempt retry due to error: #{e.message}" }
          # since we didn't raise, lets log the backtrace for debugging purposes.
          logger.debug { e.backtrace.join("\n") } unless e.backtrace.nil?
        end

        private

        # Gets the retry interval for a given attempt number
        #
        # @param retry_intervals [Array<Integer>, #call] the configured intervals or callable
        # @param attempts [Integer] the current attempt number
        # @return [Integer, nil] the interval in seconds or nil
        def get_interval(retry_intervals, attempts)
          return retry_intervals.call(attempts) if retry_intervals.respond_to?(:call)

          if attempts <= (retry_intervals = Array(retry_intervals)).size
            retry_intervals[attempts - 1]
          else
            retry_intervals.last
          end
        end

        # Calculates the next visibility timeout capped at SQS maximum
        #
        # @param interval [Integer] the desired interval
        # @param started_at [Time] when processing started
        # @return [Integer] the capped visibility timeout
        def next_visibility_timeout(interval, started_at)
          max_timeout = 43_200 - (Time.now - started_at).ceil - 1
          interval = max_timeout if interval > max_timeout
          interval.to_i
        end

        # Handles a message failure by adjusting visibility timeout
        #
        # @param sqs_msg [Shoryuken::Message] the failed message
        # @param started_at [Time] when processing started
        # @param retry_intervals [Array<Integer>, #call] the configured intervals
        # @return [Boolean] true if retry was scheduled, false otherwise
        def handle_failure(sqs_msg, started_at, retry_intervals)
          receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i

          return false unless (interval = get_interval(retry_intervals, receive_count))

          sqs_msg.change_visibility(visibility_timeout: next_visibility_timeout(interval.to_i, started_at))

          logger.info { "Message #{sqs_msg.message_id} failed, will be retried in #{interval} seconds" }

          true
        end
      end
    end
  end
end
