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
        begin
          if sqs_msg = receive_message(queue)
            logger.info "Message found #{sqs_msg}"

            @manager.async.assign(queue, sqs_msg)
          else
            logger.info "No message for #{queue}"

            after(0) { @manager.skip_and_dispatch(queue) }
          end
        rescue => ex
          logger.error("Error fetching message: #{ex}")
          logger.error(ex.backtrace.first)
          after(0) { @manager.skip_and_dispatch(queue) }
        end
      end
    end
  end
end
