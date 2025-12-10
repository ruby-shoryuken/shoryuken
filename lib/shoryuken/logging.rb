# frozen_string_literal: true

require 'time'
require 'logger'
require_relative 'logging/base'
require_relative 'logging/pretty'
require_relative 'logging/without_timestamp'

module Shoryuken
  # Provides logging functionality for Shoryuken.
  # Manages the global logger instance and thread-local context.
  module Logging
    # Executes a block with a thread-local logging context
    #
    # @param msg [String] the context message to set
    # @yield the block to execute within the context
    # @return [Object] the result of the block
    def self.with_context(msg)
      Thread.current[:shoryuken_context] = msg
      yield
    ensure
      Thread.current[:shoryuken_context] = nil
    end

    # Initializes a new logger instance
    #
    # @param log_target [IO, String] the logging target (file path or IO object)
    # @return [Logger] the initialized logger
    def self.initialize_logger(log_target = STDOUT)
      @logger = Logger.new(log_target)
      @logger.level = Logger::INFO
      @logger.formatter = Pretty.new
      @logger
    end

    # Returns the current logger instance, initializing if needed
    #
    # @return [Logger] the logger instance
    def self.logger
      @logger ||= initialize_logger
    end

    # Sets the logger instance
    #
    # @param log [Logger, nil] the logger to use, or nil for null logger
    # @return [Logger] the logger instance
    def self.logger=(log)
      @logger = log || Logger.new('/dev/null')
    end
  end
end
