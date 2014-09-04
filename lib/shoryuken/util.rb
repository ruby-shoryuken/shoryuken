module Shoryuken
  module Util
    class Pretty < Logger::Formatter
      # Provide a call() method that returns the formatted message.
      def call(severity, time, program_name, message)
        "#{time.utc.iso8601} #{Process.pid} TID-#{Thread.current.object_id.to_s(36)} #{severity}: #{message}\n"
      end
    end

    def self.logger
      @logger ||= begin
                    log = Logger.new(STDOUT)
                    log.level = Logger::INFO
                    log.formatter = Pretty.new
                    log
                  end
    end

    def watchdog(last_words)
      yield
    rescue => ex
      logger.error last_words
      logger.error ex
      logger.error ex.backtrace.join("\n")
    end

    def logger
      Shoryuken::Util.logger
    end
  end
end
