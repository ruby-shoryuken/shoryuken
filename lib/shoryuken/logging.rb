require 'time'
require 'logger'

module Shoryuken
  module Logging
    class Base < ::Logger::Formatter
      def tid
        Thread.current['shoryuken_tid'] ||= (Thread.current.object_id ^ ::Process.pid).to_s(36)
      end

      def context
        c = Thread.current[:shoryuken_context]
        c ? " #{c}" : ''
      end
    end

    class Pretty < Base
      # Provide a call() method that returns the formatted message.
      def call(severity, time, _program_name, message)
        "#{time.utc.iso8601} #{Process.pid} TID-#{tid}#{context} #{severity}: #{message}\n"
      end
    end

    class WithoutTimestamp < Base
      def call(severity, _time, _program_name, message)
        "pid=#{Process.pid} tid=#{tid}#{context} #{severity}: #{message}\n"
      end
    end

    def self.with_context(msg)
      Thread.current[:shoryuken_context] = msg
      yield
    ensure
      Thread.current[:shoryuken_context] = nil
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
