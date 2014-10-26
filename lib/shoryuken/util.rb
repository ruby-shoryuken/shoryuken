module Shoryuken
  module Util
    def watchdog(last_words)
      yield
    rescue => ex
      logger.error last_words
      logger.error ex
      logger.error ex.backtrace.join("\n")
    end

    def logger
      Shoryuken.logger
    end

    def elapsed(started_at)
      # elapsed in ms
      (Time.now - started_at) * 1000
    end

    def unparse_queues(queues)
      queues.inject({}) do |queue_and_weights, name|
        queue_and_weights[name] = queue_and_weights[name].to_i + 1
        queue_and_weights
      end.to_a
    end
  end
end
