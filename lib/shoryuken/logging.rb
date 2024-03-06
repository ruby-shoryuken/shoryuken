require 'time'
require 'logger'

class Fiber
  attr_accessor :shoryuken_context
end

module Shoryuken
  module Logging
    class Pretty < Logger::Formatter
      # Provide a call() method that returns the formatted message.
      def call(severity, time, _program_name, message)
        "#{time.utc.iso8601} #{Process.pid} TID-#{Thread.current.object_id.to_s(36)}#{context} #{severity}: #{message}\n"
      end

      def context
        Fiber.current.shoryuken_context&.then{|context| " #{context}"}
      end
    end

    def self.with_context(msg)
      Fiber.current.shoryuken_context = msg
      yield
    ensure
      Fiber.current.shoryuken_context = nil
    end

    def self.initialize_logger(log_target = STDOUT)
      @logger = Logger.new(log_target)
      @logger.level = Logger::INFO
      @logger.formatter = Pretty.new
      @logger
    end

    def self.logger
      @logger ||= initialize_logger
    end

    def self.logger=(log)
      @logger = (log || Logger.new('/dev/null'))
    end
  end
end
