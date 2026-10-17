# frozen_string_literal: true

module Shoryuken
  module Contracts
    # Validates the options a worker passes to `shoryuken_options`, so a mistyped key (e.g. `auto_delte`) is reported
    # when the worker class loads instead of being silently ignored
    class Worker < Base
      self.error_messages = load_error_messages('worker')

      # Worker options Shoryuken reads
      KNOWN_KEYS = %w[
        queue
        delete
        auto_delete
        auto_visibility_timeout
        retry_intervals
        batch
        body_parser
        non_retryable_exceptions
      ].freeze

      virtual do |data|
        (data.keys.map(&:to_s) - KNOWN_KEYS).map { |key| [[key], :unknown] }
      end
    end
  end
end
