module Shoryuken
  class Fetcher
    include Util

    FETCH_LIMIT = 10

    def initialize(group)
      @group = group
    end

    def fetch(queue, limit)
      do_with_retry(10) do
        started_at = Time.now

        logger.debug { "Looking for new messages in #{queue}" }

        sqs_msgs = Array(receive_messages(queue, [FETCH_LIMIT, limit].min))

        logger.info { "Found #{sqs_msgs.size} messages for #{queue.name}" } unless sqs_msgs.empty?
        logger.debug { "Fetcher for #{queue} completed in #{elapsed(started_at)} ms" }

        sqs_msgs
      end
    end

    private

    def do_with_retry(max_attempts, &block)
      attempts = 0

      begin
        yield
      rescue => ex
        raise if attempts >= max_attempts

        attempts += 1

        logger.debug { "Retrying fetch attempt #{attempts} for #{ex.message}" }

        sleep(attempts)

        retry
      end
    end

    def receive_messages(queue, limit)
      options = receive_options(queue)

      options[:max_number_of_messages]  = max_number_of_messages(limit, options)
      options[:message_attribute_names] = %w(All)
      options[:attribute_names]         = %w(All)

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
