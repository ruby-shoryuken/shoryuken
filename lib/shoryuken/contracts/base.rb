# frozen_string_literal: true

module Shoryuken
  module Contracts
    # Base for Shoryuken's contracts: raises {Errors::InvalidConfigurationError} and holds the checks shared by them
    class Base < Contractable::Contract
      # Path to the YAML file with the error messages of all the contracts
      ERRORS_PATH = File.expand_path('../../../config/locales/errors.yml', __dir__)

      class << self
        # Loads the error messages of one contract from the errors file
        #
        # @param section [String] the contract's section under `en.validations`
        # @return [Hash{String => String}] the error messages
        def load_error_messages(section)
          YAML.safe_load_file(ERRORS_PATH).fetch('en').fetch('validations').fetch(section)
        end

        private

        # Checks for nil or a number >= 0, also given as a String. Values such as the delay and queue weights are
        # coerced with to_f/to_i where they are used, so YAML strings and CLI values such as "2.5" work.
        #
        # @param value [Object] the value to check
        # @return [Boolean] true if the value is nil or a non-negative number
        def non_negative_number?(value)
          value.nil? || (numeric?(value) && Float(value) >= 0)
        end

        # Checks for a number, or a String holding one
        #
        # @param value [Object] the value to check
        # @return [Boolean] true if the value is numeric
        def numeric?(value)
          return true if value.is_a?(Numeric)

          value.is_a?(String) && !Float(value, exception: false).nil?
        end

        # Checks a list of queues: names, or names with an optional weight
        #
        # @param value [Object] the queues
        # @return [Boolean] true if the value is nil or a valid list of queues
        def valid_queues?(value)
          value.nil? || (value.is_a?(Array) && value.all? { |queue| valid_queue?(queue) })
        end

        # Checks a single queue entry: a name, or a name with an optional weight
        #
        # @param queue [Object] the queue entry
        # @return [Boolean] true if the entry is valid
        def valid_queue?(queue)
          return valid_queue_name?(queue) unless queue.is_a?(Array)
          return false unless (1..2).cover?(queue.size) && valid_queue_name?(queue.first)

          queue[1].nil? || numeric?(queue[1])
        end

        # Checks a queue name, URL or ARN
        #
        # @param name [Object] the queue name, URL or ARN
        # @return [Boolean] true if the name is a non-empty String or Symbol
        def valid_queue_name?(name)
          (name.is_a?(String) || name.is_a?(Symbol)) && !name.empty?
        end
      end

      # Validates the data and raises when it is invalid
      #
      # @param data [Hash] data for validation
      # @param scope [Array<Symbol>] scope of this contract, empty when it starts from the root
      # @return [Boolean] true
      # @raise [Errors::InvalidConfigurationError] when the data is invalid
      def validate!(data, scope: [])
        super(data, Errors::InvalidConfigurationError, scope: scope)
      end
    end
  end
end
