# frozen_string_literal: true

module Shoryuken
  module Contractable
    # Representation of a validaton result with resolved error messages
    class Result
      # @return [Hash{Symbol => String}] error messages keyed by the dotted path of the invalid key
      attr_reader :errors

      # Empty hash that we use when no errors to save on allocations
      EMPTY_HASH = {}.freeze

      private_constant :EMPTY_HASH

      class << self
        # @return [Result] cached frozen success result to avoid allocating a new Result on
        #   every successful contract validation. Safe because successful results are
        #   identical regardless of contract (they all have @errors = EMPTY_HASH).
        def success
          @success ||= new([], nil).freeze
        end
      end

      # Builds a result object and remaps (if needed) error keys to proper error messages
      #
      # @param errors [Array<Array>] array with sub-arrays with paths and error keys
      # @param contract [Object] contract that generated the error
      def initialize(errors, contract)
        # Short track to skip object allocation for the happy path
        if errors.empty?
          @errors = EMPTY_HASH
          return
        end

        hashed = {}

        errors.each do |error|
          scope = error.first.map(&:to_s).join('.').to_sym

          # This will allow for usage of custom messages instead of yaml keys if needed
          hashed[scope] = if error.last.is_a?(String)
                            error.last
                          else
                            build_message(contract, scope, error.last)
                          end
        end

        @errors = hashed
      end

      # Checks whether the validation passed
      #
      # @return [Boolean] true if no errors
      def success?
        errors.empty?
      end

      private

      # Builds message based on the error messages and scope
      #
      # @param contract [Object] contract for which we build the result
      # @param scope [Symbol] path to the key that has an error
      # @param error_key [Symbol] error key for yaml errors lookup
      # @return [String] error message
      def build_message(contract, scope, error_key)
        messages = contract.class.error_messages

        # Split scope into parts for progressive checking
        scope_parts = scope.to_s.split('.')

        # Try full scope first, then progressively remove from beginning
        # This allows us to have full path scoped errors but can also be used as a fallback,
        # when scopes are dynamic. For example 'group_name.queues_format'
        (0..scope_parts.length).each do |i|
          current_scope_parts = scope_parts[i..]

          key = if current_scope_parts.empty?
                  error_key.to_s
                else
                  "#{current_scope_parts.join('.')}_#{error_key}"
                end

          return messages[key] if messages.key?(key)
        end

        # If nothing found, raise the original error
        messages.fetch(error_key.to_s) do
          messages.fetch("#{scope}_#{error_key}")
        end
      end
    end
  end
end
