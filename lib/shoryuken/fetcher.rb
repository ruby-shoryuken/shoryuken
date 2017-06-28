module Shoryuken
  class Fetcher
    include Util

    FETCH_LIMIT = 10

    attr_reader :group

    def initialize(group)
      @group = group
    end

    def fetch(queue, limit)
      started_at = Time.now

      logger.debug { "Looking for new messages in #{queue}" }

      sqs_msgs = Array(receive_messages(queue, [FETCH_LIMIT, limit].min))

      logger.info { "Found #{sqs_msgs.size} messages for #{queue.name}" } unless sqs_msgs.empty?
      logger.debug { "Fetcher for #{queue} completed in #{elapsed(started_at)} ms" }

      sqs_msgs
    end

    private

    def receive_messages(queue, limit)
      # AWS limits the batch size by 10
      limit = limit > FETCH_LIMIT ? FETCH_LIMIT : limit

      options = Shoryuken.sqs_client_receive_message_opts[group].to_h.dup

      options[:max_number_of_messages]  = limit
      options[:message_attribute_names] = %w(All)
      options[:attribute_names]         = %w(All)

      options.merge!(queue.options)

      Shoryuken::Client.queues(queue.name).receive_messages(options)
    end
  end
end
