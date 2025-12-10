# frozen_string_literal: true

module Shoryuken
  module Logging
    # A pretty log formatter that includes timestamps, process ID, thread ID,
    # context information, and severity in a human-readable format.
    #
    # Output format: "TIMESTAMP PID TID-THREAD_ID CONTEXT SEVERITY: MESSAGE"
    #
    # @example Output
    #   "2023-08-15T10:30:45Z 12345 TID-abc123 MyWorker/queue1/msg-456 INFO: Processing message"
    class Pretty < Base
      # Formats a log message with timestamp and full context information.
      #
      # @param severity [String] Log severity level (DEBUG, INFO, WARN, ERROR, FATAL)
      # @param time [Time] Timestamp when the log entry was created
      # @param _program_name [String] Program name (unused)
      # @param message [String] The log message
      # @return [String] Formatted log entry with newline
      def call(severity, time, _program_name, message)
        "#{time.utc.iso8601} #{Process.pid} TID-#{tid}#{context} #{severity}: #{message}\n"
      end
    end
  end
end
