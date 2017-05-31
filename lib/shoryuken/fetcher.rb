module Shoryuken
  class Fetcher
    include Util

    FETCH_LIMIT = 10

    def fetch(queue, available_processors)
      started_at = Time.now

      logger.debug { "Looking for new messages in '#{queue}'" }

      limit = available_processors > FETCH_LIMIT ? FETCH_LIMIT : available_processors

      sqs_msgs = Array(receive_messages(queue, limit))
      logger.info { "Found #{sqs_msgs.size} messages for '#{queue.name}'" } unless sqs_msgs.empty?
      logger.debug { "Fetcher for '#{queue}' completed in #{elapsed(started_at)} ms" }
      sqs_msgs
    end

    private

    def receive_messages(queue, limit)
      # AWS limits the batch size by 10
      limit = limit > FETCH_LIMIT ? FETCH_LIMIT : limit

      options = Shoryuken.sqs_client_receive_message_opts.to_h.dup
      options[:max_number_of_messages] = limit
      options[:message_attribute_names] = %w(All)
      options[:attribute_names] = %w(All)

      options.merge!(queue.options)

      begin
        Shoryuken::Client.queues(queue.name).receive_messages(options)
      rescue => ex
        raise ex if options[:raise_errors]

        logger.error { "Error fetching message: #{ex}" }
        logger.error { ex.backtrace.first }
        []
      end
    end
  end
end
