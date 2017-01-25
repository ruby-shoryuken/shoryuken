module Shoryuken
  class Fetcher
    include Util

    FETCH_LIMIT = 10

    def fetch(queue, available_processors)
      watchdog('Fetcher#fetch died') do
        started_at = Time.now

        logger.debug { "Looking for new messages in '#{queue}'" }

        begin
          limit = available_processors > FETCH_LIMIT ? FETCH_LIMIT : available_processors

          sqs_msgs = Array(receive_messages(queue, limit))
          logger.info { "Found #{sqs_msgs.size} messages for '#{queue.name}'" } if !sqs_msgs.empty?
          logger.debug { "Fetcher for '#{queue}' completed in #{elapsed(started_at)} ms" }
          sqs_msgs
        rescue => ex
          logger.error { "Error fetching message: #{ex}" }
          logger.error { ex.backtrace.first }
          []
        end
      end
    end

    private

    def receive_messages(queue, limit)
      # AWS limits the batch size by 10
      limit = limit > FETCH_LIMIT ? FETCH_LIMIT : limit

      options = (Shoryuken.options[:aws][:receive_message] || {}).dup
      options[:max_number_of_messages] = limit
      options[:message_attribute_names] = %w(All)
      options[:attribute_names] = %w(All)

      options.merge!(queue.options)

      Shoryuken::Client.queues(queue.name).receive_messages(options)
    end
  end
end
