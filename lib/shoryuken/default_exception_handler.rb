module Shoryuken
  class DefaultExceptionHandler
    extend Util

    def self.call(exception, _queue, _sqs_msg)
      logger.error { "Processor failed: #{exception.message}" }
      logger.error { exception.backtrace.join("\n") } if exception.backtrace
    end
  end
end
