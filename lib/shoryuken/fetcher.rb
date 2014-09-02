module Shoryuken
  class Fetcher
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def retrieve_work(queue)
      queue.receive_message
    end

    def fetch(queue)
      if sqs_msg = retrieve_work(queue)
        logger.info "Message found #{sqs_msg}"

        @manager.assign(queue, sqs_msg)
      else
        logger.info "No message for #{queue}"

        after(0) { @manager.skip_and_dispatch(queue) }
      end
    end
  end
end
