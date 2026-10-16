# frozen_string_literal: true

module Shoryuken
  # Validates the global options (YAML config file, CLI and Ruby code) once they are loaded, so a mistyped or invalid
  # setting is reported instead of being silently ignored or failing later at runtime.
  #
  # Invalid values raise {Errors::InvalidConfigurationError}. Unknown keys only log a warning: applications and
  # extensions may keep their own keys in the options and the config file, so rejecting them would break working setups.
  class OptionsContract
    include Util

    # Checks shared by the global options and the options of a processing group
    GROUP_RULES = {
      concurrency: ->(value) { value.is_a?(Integer) && value.positive? },
      delay: ->(value) { value.nil? || (value.is_a?(Numeric) && value >= 0) },
      polling_strategy: ->(value) { value.nil? || value.is_a?(String) || value.is_a?(Class) },
      queues: ->(value) { value.nil? || (value.is_a?(Array) && value.all? { |queue| valid_queue?(queue) }) }
    }.freeze

    # Checks for each known global option
    RULES = GROUP_RULES.merge(
      timeout: ->(value) { value.nil? || (value.is_a?(Numeric) && value >= 0) },
      thread_priority: ->(value) { value.is_a?(Integer) },
      aws: ->(value) { value.is_a?(Hash) },
      groups: ->(value) { value.nil? || value.is_a?(Hash) || value.is_a?(Array) },
      lifecycle_events: ->(value) { value.is_a?(Hash) },
      config_file: ->(value) { value.nil? || value.is_a?(String) || value.respond_to?(:to_path) },
      require: ->(value) { value.nil? || value.is_a?(String) },
      logfile: ->(value) { value.nil? || value.is_a?(String) },
      pidfile: ->(value) { value.nil? || value.is_a?(String) },
      daemon: ->(value) { [nil, true, false].include?(value) },
      rails: ->(value) { [nil, true, false].include?(value) },
      verbose: ->(value) { [nil, true, false].include?(value) }
    ).freeze

    # Group options that may be left unset, in which case the global value is used
    OPTIONAL_GROUP_KEYS = %i[concurrency].freeze

    private_constant :GROUP_RULES, :RULES, :OPTIONAL_GROUP_KEYS

    class << self
      # Validates the given options
      #
      # @param config [Hash] the options to validate
      # @return [void]
      # @raise [Errors::InvalidConfigurationError] when an option has an invalid value
      def validate!(config)
        new.validate!(config)
      end

      # Checks a single queue entry: a name, or a name with an optional weight
      #
      # @param queue [Object] the queue entry
      # @return [Boolean] true if the entry is valid
      def valid_queue?(queue)
        return valid_queue_name?(queue) unless queue.is_a?(Array)
        return false unless (1..2).cover?(queue.size) && valid_queue_name?(queue.first)

        weight = queue[1]
        weight.nil? || weight.is_a?(Integer) || (weight.is_a?(String) && weight.match?(/\A\d+\z/))
      end

      private

      # @param name [Object] the queue name, URL or ARN
      # @return [Boolean] true if the name is a non-empty String or Symbol
      def valid_queue_name?(name)
        (name.is_a?(String) || name.is_a?(Symbol)) && !name.empty?
      end
    end

    # Validates the given options
    #
    # @param config [Hash] the options to validate
    # @return [void]
    # @raise [Errors::InvalidConfigurationError] when an option has an invalid value
    def validate!(config)
      check(config, RULES, 'options')

      config[:groups].to_a.each do |group, group_options|
        scope = "groups.#{group}"
        raise Errors::InvalidConfigurationError, "Invalid #{scope}: must be a Hash" unless group_options.is_a?(Hash)

        check(group_options.reject { |key, value| value.nil? && OPTIONAL_GROUP_KEYS.include?(key) }, GROUP_RULES, scope)
      end
    end

    private

    # @param values [Hash] the options to check
    # @param rules [Hash{Symbol => Proc}] the checks per known key
    # @param scope [String] where the options come from, used in messages
    # @return [void]
    def check(values, rules, scope)
      values.each do |key, value|
        rule = rules[key]

        if rule.nil?
          logger.warn { "Unknown option '#{qualified(scope, key)}' is ignored; check it for a typo" }
          next
        end

        next if rule.call(value)

        raise Errors::InvalidConfigurationError, "Invalid value for #{qualified(scope, key)}: #{value.inspect}"
      end
    end

    # @param scope [String] where the option comes from
    # @param key [Symbol] the option name
    # @return [String] the option name, with its group when it belongs to one
    def qualified(scope, key)
      scope == 'options' ? key.to_s : "#{scope}.#{key}"
    end
  end
end
