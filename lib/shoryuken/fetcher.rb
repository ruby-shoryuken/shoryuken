module Shoryuken
  class Fetcher
    include Util

    FETCH_LIMIT = 10

    def initialize(group)
      @group = group
    end

    def fetch(queue, limit)
      fetch_with_auto_retry(3) do
        started_at = Time.now

        logger.debug { "Looking for new messages in #{queue}" }

        sqs_msgs = Array(receive_messages(queue, [FETCH_LIMIT, limit].min))

        logger.debug { "Found #{sqs_msgs.size} messages for #{queue.name}" } unless sqs_msgs.empty?
        logger.debug { "Fetcher for #{queue} completed in #{elapsed(started_at)} ms" }

        sqs_msgs
      end
    end

    private

    def fetch_with_auto_retry(max_attempts)
      attempts = 0

      begin
        yield
      rescue => ex
        # Tries to auto retry connectivity errors
        raise if attempts >= max_attempts

        attempts += 1

        logger.debug { "Retrying fetch attempt #{attempts} for #{ex.message}" }

        sleep((1..5).to_a.sample)

        retry
      end
    end

    def receive_messages(queue, limit)
      options = receive_options(queue)

      options[:max_number_of_messages]  = max_number_of_messages(limit, options)
      options[:message_attribute_names] = %w[All]
      options[:attribute_names]         = %w[All]

      options.merge!(queue.options)

      Shoryuken::Client.queues(queue.name).receive_messages(options)
    end

    def max_number_of_messages(limit, options)
      [limit, FETCH_LIMIT, options[:max_number_of_messages]].compact.min
    end

    def receive_options(queue)
      options = Shoryuken.sqs_client_receive_message_opts[queue.name]
      options ||= Shoryuken.sqs_client_receive_message_opts[@group]

      options.to_h.dup
    end
  end
end
