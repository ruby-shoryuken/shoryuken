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

        sqs_msgs = Array(receive_messages(queue, limit))

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

      shoryuken_queue = Shoryuken::Client.queues(queue.name)

      options[:max_number_of_messages]  = max_number_of_messages(shoryuken_queue, limit, options)
      options[:message_attribute_names] = %w[All]
      options[:attribute_names]         = %w[All]

      options.merge!(queue.options)

      shoryuken_queue.receive_messages(options)
    end

    def max_number_of_messages(shoryuken_queue, limit, options)
      # For FIFO queues we want to make sure we process one message per group at a time
      # if we set max_number_of_messages greater than 1,
      # SQS may return more than one message for the same message group
      # since Shoryuken uses threads, it will try to process more than one message at once
      # > The message group ID is the tag that specifies that a message belongs to a specific message group.
      # > Messages that belong to the same message group are always processed one by one,
      # > in a strict order relative to the message group
      # > (however, messages that belong to different message groups might be processed out of order).
      # > https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/using-messagegroupid-property.html
      limit = 1 if shoryuken_queue.fifo? && !batched_queue?(shoryuken_queue)

      [limit, FETCH_LIMIT, options[:max_number_of_messages]].compact.min
    end

    def receive_options(queue)
      options = Shoryuken.sqs_client_receive_message_opts[queue.name]
      options ||= Shoryuken.sqs_client_receive_message_opts[@group]

      options.to_h.dup
    end

    def batched_queue?(queue)
      Shoryuken.worker_registry.batch_receive_messages?(queue.name)
    end
  end
end
