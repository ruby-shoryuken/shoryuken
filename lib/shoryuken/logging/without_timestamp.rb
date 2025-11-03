# frozen_string_literal: true

require_relative 'base'

module Shoryuken
  module Logging
    # A log formatter that excludes timestamps from output.
    # Useful for environments where timestamps are added by external logging systems.
    #
    # Output format: "pid=PID tid=THREAD_ID CONTEXT SEVERITY: MESSAGE"
    #
    # @example Output
    #   pid=12345 tid=abc123 MyWorker/queue1/msg-456 INFO: Processing message
    class WithoutTimestamp < Base
      # Formats a log message without timestamp information.
      #
      # @param severity [String] Log severity level (DEBUG, INFO, WARN, ERROR, FATAL)
      # @param _time [Time] Timestamp (unused)
      # @param _program_name [String] Program name (unused)
      # @param message [String] The log message
      # @return [String] Formatted log entry with newline
      def call(severity, _time, _program_name, message)
        "pid=#{Process.pid} tid=#{tid}#{context} #{severity}: #{message}\n"
      end
    end
  end
end