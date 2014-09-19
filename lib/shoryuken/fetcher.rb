module Shoryuken
  class Fetcher
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def receive_message(queue)
      Shoryuken::Client.receive_message queue, Shoryuken.options[:aws][:receive_message]
    end

    def fetch(queue)
      watchdog('Fetcher#fetch died') do
        beginning_time = Time.now

        logger.info "Looking for new messages queue '#{queue}'"

        begin
          if sqs_msg = receive_message(queue)
            logger.info "Message found for queue '#{queue}'"

            @manager.async.rebalance_queue_weight!(queue)

            @manager.async.assign(queue, sqs_msg)
          else
            logger.info "No message found for queue '#{queue}'"

            @manager.async.pause_queue!(queue)

            after(0) { @manager.dispatch }
          end

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
