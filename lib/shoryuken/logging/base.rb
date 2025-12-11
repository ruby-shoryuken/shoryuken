# frozen_string_literal: true

module Shoryuken
  module Logging
    # Base formatter class that provides common functionality for Shoryuken log formatters.
    # Provides thread ID generation and context management.
    class Base < ::Logger::Formatter
      # Generates a thread ID for the current thread.
      # Uses a combination of thread object_id and process ID to create a unique identifier.
      #
      # @return [String] A base36-encoded thread identifier
      def tid
        Thread.current['shoryuken_tid'] ||= (Thread.current.object_id ^ ::Process.pid).to_s(36)
      end

      # Returns the current logging context as a formatted string.
      # Context is set using {Shoryuken::Logging.with_context}.
      #
      # @return [String] Formatted context string or empty string if no context
      def context
        c = Shoryuken::Logging.current_context
        c ? " #{c}" : ''
      end
    end
  end
end
