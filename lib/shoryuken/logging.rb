# frozen_string_literal: true

require 'time'
require 'logger'
require_relative 'logging/base'
require_relative 'logging/pretty'
require_relative 'logging/without_timestamp'

module Shoryuken
  # Provides logging functionality for Shoryuken.
  # Manages the global logger instance and fiber-local context.
  module Logging
    # Executes a block with a fiber-local logging context.
    # Uses Fiber storage (Ruby 3.2+) for proper isolation in async environments.
    #
    # @param msg [String] the context message to set
    # @yield the block to execute within the context
    # @return [Object] the result of the block
    def self.with_context(msg)
      previous = context_storage[:shoryuken_context]
      context_storage[:shoryuken_context] = msg
      yield
    ensure
      context_storage[:shoryuken_context] = previous
    end

    # Returns the current logging context value
    #
    # @return [String, nil] the current context or nil if not set
    def self.current_context
      context_storage[:shoryuken_context]
    end

    # Returns the Fiber class for fiber-local context storage.
    # Uses Fiber[] and Fiber[]= (Ruby 3.2+) for proper isolation in async environments.
    #
    # @return [Class] the Fiber class
    def self.context_storage
      Fiber
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
