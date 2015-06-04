module Shoryuken
  class Fetcher
    include Celluloid
    include Util

    FETCH_LIMIT = 10

    def initialize(manager)
      @manager = manager
    end

    def fetch(queue, available_processors)
      watchdog('Fetcher#fetch died') do
        started_at = Time.now

        logger.debug { "Looking for new messages in '#{queue}'" }

        begin
          batch = Shoryuken.worker_registry.batch_receive_messages?(queue.name)
          limit = batch ? FETCH_LIMIT : available_processors

          if (sqs_msgs = Array(receive_messages(queue, limit))).any?
            logger.debug { "Found #{sqs_msgs.size} messages for '#{queue}'" }

            if batch
              @manager.async.assign(queue.name, patch_sqs_msgs!(sqs_msgs))
            else
              sqs_msgs.each { |sqs_msg| @manager.async.assign(queue.name, sqs_msg) }
            end

            @manager.async.messages_present(queue)
          else
            logger.debug { "No message found for '#{queue}'" }

            @manager.async.queue_empty(queue)
          end

          logger.debug { "Fetcher for '#{queue}' completed in #{elapsed(started_at)} ms" }
        rescue => ex
          logger.error { "Error fetching message: #{ex}" }
          logger.error { ex.backtrace.first }
        end

        @manager.async.dispatch
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

      Shoryuken::Client.queues(queue.name).receive_messages options
    end

    def patch_sqs_msgs!(sqs_msgs)
      sqs_msgs.instance_eval do
        def message_id
          "batch-with-#{size}-messages"
        end
      end

      sqs_msgs
    end
  end
end
