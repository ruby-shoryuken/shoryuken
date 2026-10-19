# frozen_string_literal: true

module Shoryuken
  module Contracts
    # Validates the global options (YAML config file, CLI and Ruby code) once they are loaded, so a mistyped or invalid
    # setting is reported instead of being silently ignored or failing later at runtime.
    #
    # Invalid values raise {Errors::InvalidConfigurationError}. Unknown keys only log a warning: applications and
    # extensions may keep their own keys in the options and the config file, so rejecting them would break working
    # setups.
    class Options < Base
      include Util

      self.error_messages = load_error_messages('options')

      optional(:concurrency) { |value| value.is_a?(Integer) && value.positive? }
      optional(:delay) { |value| non_negative_number?(value) }
      optional(:timeout) { |value| value.nil? || (value.is_a?(Numeric) && value >= 0) }
      optional(:polling_strategy) { |value| value.nil? || value.is_a?(String) || value.is_a?(Class) }
      optional(:queues) { |value| valid_queues?(value) }
      optional(:groups) { |value| value.nil? || value.is_a?(Hash) || value.is_a?(Array) }
      optional(:thread_priority) { |value| value.is_a?(Integer) }
      optional(:aws) { |value| value.is_a?(Hash) }
      optional(:lifecycle_events) { |value| value.is_a?(Hash) }
      optional(:config_file) { |value| value.nil? || value.is_a?(String) || value.respond_to?(:to_path) }
      optional(:require) { |value| value.nil? || value.is_a?(String) }
      optional(:logfile) { |value| value.nil? || value.is_a?(String) }
      optional(:pidfile) { |value| value.nil? || value.is_a?(String) }
      optional(:daemon) { |value| [nil, true, false].include?(value) }
      optional(:rails) { |value| [nil, true, false].include?(value) }
      optional(:verbose) { |value| [nil, true, false].include?(value) }

      # Group names are dynamic, so each group is checked with its own contract
      virtual do |data|
        groups = data[:groups]
        next true unless groups.is_a?(Hash) || groups.is_a?(Array)

        groups.to_a.flat_map do |name, group|
          next [[[:groups, name], :group_format]] unless group.is_a?(Hash)

          Group.new.call(group).errors.map do |path, message|
            [[:groups, name, *path.to_s.split('.').map(&:to_sym)], message]
          end
        end
      end

      # Warns about unknown keys, then validates the options
      #
      # @param data [Hash] the options
      # @param scope [Array<Symbol>] scope of this contract, empty when it starts from the root
      # @return [Boolean] true
      # @raise [Errors::InvalidConfigurationError] when an option has an invalid value
      def validate!(data, scope: [])
        warn_unknown_keys(data)

        super
      end

      private

      # Logs a warning for each option, global or in a group, that no rule knows
      #
      # @param data [Hash] the options
      # @return [void]
      def warn_unknown_keys(data)
        unknown = (data.keys - known_keys(self.class)).map(&:to_s)

        groups = data[:groups]
        if groups.is_a?(Hash) || groups.is_a?(Array)
          groups.to_a.each do |name, group|
            next unless group.is_a?(Hash)

            unknown.concat((group.keys - known_keys(Group)).map { |key| "groups.#{name}.#{key}" })
          end
        end

        unknown.each do |key|
          logger.warn { "Unknown option '#{key}' is ignored; check it for a typo" }
        end
      end

      # Lists the keys a contract has rules for
      #
      # @param contract [Class] the contract class
      # @return [Array<Symbol>] the known keys
      def known_keys(contract)
        contract.rules.map { |rule| rule.path.first }.compact
      end
    end
  end
end
