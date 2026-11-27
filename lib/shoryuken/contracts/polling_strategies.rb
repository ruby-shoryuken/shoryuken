# frozen_string_literal: true

module Shoryuken
  module Contracts
    # Validates that each polling strategy given by name, globally or in a group, resolves to a strategy. A custom
    # strategy can be defined in a required file, so this runs after the workers are required, unlike {Options}, which
    # already checked the types.
    #
    # An unknown name raises {Errors::InvalidPollingStrategyError}, so it does not inherit {Base}, which raises
    # {Errors::InvalidConfigurationError}.
    class PollingStrategies < Contractable::Contract
      self.error_messages = Base.load_error_messages('polling_strategies')

      class << self
        private

        # Checks that a strategy setting resolves with {Options#resolve_polling_strategy}
        #
        # @param value [Object] the polling strategy
        # @return [Boolean] true if the value resolves
        def resolvable?(value)
          Shoryuken.resolve_polling_strategy(value)
          true
        rescue Errors::InvalidPollingStrategyError
          false
        end
      end

      # The global strategy is used only by the default group, which exists only with top-level queues
      optional(:polling_strategy) { |value, data| data[:queues].to_a.empty? || resolvable?(value) }

      virtual do |data|
        groups = data[:groups]
        next true unless groups.is_a?(Hash) || groups.is_a?(Array)

        groups.to_a.filter_map do |name, group|
          next unless group.is_a?(Hash)
          next if resolvable?(group[:polling_strategy])

          [[:groups, name, :polling_strategy], :format]
        end
      end

      # Validates the data and raises when a strategy name does not resolve
      #
      # @param data [Hash] the options
      # @param scope [Array<Symbol>] scope of this contract, empty when it starts from the root
      # @return [Boolean] true
      # @raise [Errors::InvalidPollingStrategyError] when a strategy name does not resolve
      def validate!(data, scope: [])
        super(data, Errors::InvalidPollingStrategyError, scope: scope)
      end
    end
  end
end
