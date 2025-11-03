# frozen_string_literal: true

require 'time'
require 'logger'
require_relative 'logging/base'
require_relative 'logging/pretty'
require_relative 'logging/without_timestamp'

module Shoryuken
  module Logging

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
      @logger = log || Logger.new('/dev/null')
    end
  end
end
