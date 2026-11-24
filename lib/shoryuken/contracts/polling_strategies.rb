# frozen_string_literal: true

module Shoryuken
  module Contracts
    # Validates that each polling strategy given by name, globally or in a group, resolves to a strategy. A custom
    # strategy can be defined in a required file, so this runs after the workers are required, unlike {Options}, which
    # already checked the types.
    #
    # An unknown name raises {Errors::InvalidPollingStrategyError}.
    class PollingStrategies < Contractable::Contract
      # Names of the built-in strategies, resolved without a constant lookup
      BUILT_IN = %w[WeightedRoundRobin StrictPriority].freeze

      private_constant :BUILT_IN

      self.error_messages = Base.load_error_messages('polling_strategies')

      class << self
        private

        # Checks that a strategy name resolves the way {Options#polling_strategy} resolves it
        #
        # @param value [Object] the polling strategy
        # @return [Boolean] true if the value is not a String, a built-in name or the name of a defined constant
        def resolvable?(value)
          return true unless value.is_a?(String)
          return true if BUILT_IN.include?(value)

          Object.const_get(value)
          true
        rescue NameError
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
