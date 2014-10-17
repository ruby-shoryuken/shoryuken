module Shoryuken
  class Fetcher
    include Celluloid
    include Util

    FETCH_LIMIT = 10

    def initialize(manager)
      @manager = manager
    end

    def receive_message(queue, limit)
      # AWS limits the batch size by 10
      limit = limit > FETCH_LIMIT ? FETCH_LIMIT : limit

      Shoryuken::Client.receive_message queue, Shoryuken.options[:aws][:receive_message].to_h.merge(limit: limit)
    end

    def fetch(queue, available_processors)
      watchdog('Fetcher#fetch died') do
        started_at = Time.now

        logger.info "Looking for new messages '#{queue}'"

        begin
          batch = !!Shoryuken.workers[queue].get_shoryuken_options['batch']

          limit = batch ? FETCH_LIMIT : available_processors

          if (sqs_msgs = Array(receive_message(queue, limit))).any?
            logger.info "Found #{sqs_msgs.size} messages for '#{queue}'"

            if batch
              @manager.async.assign(queue, sqs_msgs)
            else
              sqs_msgs.each { |sqs_msg| @manager.async.assign(queue, sqs_msg) }
            end

            @manager.async.rebalance_queue_weight!(queue)
          else
            logger.info "No message found for '#{queue}'"

            @manager.async.pause_queue!(queue)
          end

          @manager.async.dispatch

          logger.debug { "Fetcher for '#{queue}' completed in #{elapsed(started_at)} ms" }
        rescue => ex
          logger.error "Error fetching message: #{ex}"
          logger.error ex.backtrace.first

          @manager.async.dispatch
        end
      end
    end
  end
end
