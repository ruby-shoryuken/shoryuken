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

      private_constant :KNOWN_KEYS

      class << self
        private

        # Checks for a body parser BodyParser can use, so a typo fails when the worker loads instead of every message
        # getting a nil body
        #
        # @param value [Object] the body_parser option
        # @return [Boolean] true if the value is nil, :json, :text, a Proc or responds to parse or load
        def valid_body_parser?(value)
          [nil, :json, :text].include?(value) ||
            value.is_a?(Proc) ||
            value.respond_to?(:parse) ||
            value.respond_to?(:load)
        end
      end

      optional('body_parser') { |value| valid_body_parser?(value) }

      virtual do |data|
        (data.keys.map(&:to_s) - KNOWN_KEYS).map { |key| [[key], :unknown] }
      end
    end
  end
end
