module Shoryuken
  class Fetcher
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def receive_message(queue, limit)
      limit = limit > 10 ? 10 : limit

      Shoryuken::Client.receive_message queue, Shoryuken.options[:aws][:receive_message].to_h.merge(limit: limit)
    end

    def fetch(queue, available_processors)
      watchdog('Fetcher#fetch died') do
        beginning_time = Time.now

        logger.info "Looking for new messages queue '#{queue}'"

        begin
          if (sqs_msgs = Array(receive_message(queue, available_processors))).any?
            logger.info "Message found for queue '#{queue}'"

            sqs_msgs.each do |sqs_msg|
              @manager.async.rebalance_queue_weight!(queue)
              @manager.async.assign(queue, sqs_msg)
            end
          else
            logger.info "No message found for queue '#{queue}'"

            @manager.async.pause_queue!(queue)
          end

          @manager.async.dispatch

          logger.debug "Fetcher#fetch('#{queue}') completed in #{(Time.now - beginning_time) * 1000} ms"
        rescue => ex
          logger.error("Error fetching message: #{ex}")
          logger.error(ex.backtrace.first)

          @manager.async.dispatch
        end
      end
    end
  end
end
