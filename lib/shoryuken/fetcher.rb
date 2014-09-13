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
        logger.info "Looking for new messages queue '#{queue}'"

        begin
          if sqs_msg = receive_message(queue)
            logger.info "Message found for queue '#{queue}'"

            @manager.async.assign(queue, sqs_msg)
          else
            logger.info "No message found for queue '#{queue}'"

            @manager.async.work_not_found!(queue)

            after((Shoryuken.options[:delay] || 0).to_i) { @manager.dispatch }
          end
        rescue => ex
          logger.error("Error fetching message: #{ex}")
          logger.error(ex.backtrace.first)

          @manager.async.dispatch
        end
      end
    end
  end
end
