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
  end
end
