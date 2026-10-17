# frozen_string_literal: true

module Shoryuken
  module Contractable
    # Base contract for all the contracts that check data format
    #
    # @note This contract does NOT support rules inheritance
    class Contract
      # Constant representing a miss during dig. We use it as a result value not to return an array with found object
      # and a state to prevent additional array allocation
      DIG_MISS = Object.new

      # Empty array for scope default to avoid allocating a new Array on each `#call` / `#validate!` invocation. Safe
      # because scope is never mutated - it is only used in `scope + rule.path` which creates a new Array.
      EMPTY_ARRAY = [].freeze

      private_constant :DIG_MISS, :EMPTY_ARRAY

      # Class level API definitions
      class << self
        # @return [Array<Rule>] all the validation rules defined for a given contract
        attr_reader :rules

        # @return [Hash{String => String}] error messages keyed by error key (yaml based)
        attr_writer :error_messages

        # Error messages used to build the result messages. Inherited from the parent contract when not set.
        #
        # @return [Hash{String => String}] error messages keyed by error key
        def error_messages
          @error_messages || (superclass.respond_to?(:error_messages) ? superclass.error_messages : {})
        end

        # Allows for definition of a scope/namespace for nested validations
        #
        # @param path [Symbol] path in the hash for nesting
        # @return [void]
        #
        # @example
        #   nested(:key) do
        #     required(:inside) { |inside| inside.is_a?(String) }
        #   end
        def nested(path, &)
          init_accu
          @nested << path
          begin
            instance_eval(&)
          ensure
            # Always pop, even if the block raises. Otherwise a rescued exception during
            # contract definition would leave `path` on @nested and prefix it onto every rule
            # defined afterwards.
            @nested.pop
          end
        end

        # Defines a rule for a required field (required means, that will automatically create an error if missing)
        #
        # @param keys [Array<Symbol>] single or full path
        # @param block [Proc] validation rule
        # @return [Array<Rule>] the rules defined so far
        def required(*keys, &block)
          init_accu
          @rules << Rule.new(@nested + keys, :required, block).freeze
        end

        # Defines a rule for an optional field (validated only when present)
        #
        # @param keys [Array<Symbol>] single or full path
        # @param block [Proc] validation rule
        # @return [Array<Rule>] the rules defined so far
        def optional(*keys, &block)
          init_accu
          @rules << Rule.new(@nested + keys, :optional, block).freeze
        end

        # Defines a virtual rule that validates the whole data rather than a single key. Unlike
        # `required`/`optional`, the block receives the full data and returns its own errors.
        #
        # @param block [Proc] validation rule, called with `(data, errors, contract)`. It must
        #   return either a non-Array (`true`/`nil`/`false`) for "no errors", or an `Array` of
        #   `[path, message]` error pairs (where `path` is itself an `Array` of symbols).
        # @return [Array<Rule>] the rules defined so far
        #
        # @note The returned error `Array` is owned by the contract: `#call` prepends the current
        #   scope onto each pair in place and collects them, so a rule must return a freshly
        #   built `Array` on every call. Returning a memoized, shared or frozen `Array` is not
        #   supported -- in-place scoping would accumulate the prefix across validations (or
        #   raise `FrozenError`). Build the result in the block (e.g. `[[%i[id], :invalid]]`)
        #   rather than returning a constant.
        def virtual(&block)
          init_accu
          @rules << Rule.new([], :virtual, block).freeze
        end

        private

        # Initializes nestings and rules building accumulator
        #
        # @return [void]
        def init_accu
          @nested ||= []
          @rules ||= []
        end
      end

      # Runs the validation
      #
      # The per-rule handling is inlined instead of dispatching to per-type methods. Required and
      # optional rules share the whole flow except the missing-key handling. `DIG_MISS` is compared
      # via `#equal?` so we never dispatch `#==` to the validated (user-provided) values.
      #
      # @param data [Hash] hash with data we want to validate
      # @param scope [Array<String>] scope of this contract (if any) or empty array if no parent
      #   scope is needed if contract starts from root
      # @return [Result] validaton result
      def call(data, scope: EMPTY_ARRAY)
        errors = []

        # A non-Hash root has no keys to dig; resolve it once here so #dig stays on its lean
        # fast path and is only invoked with a Hash. Non-Hash data makes every required rule
        # report missing, consistent with the non-Hash intermediate handling inside #dig.
        data_is_hash = data.is_a?(Hash)

        self.class.rules.each do |rule|
          if rule.type == :virtual
            result = rule.validator.call(data, errors, self)

            # A virtual rule signals "no errors" with any non-Array result (true, but also a
            # falsy `nil`/`false` returned by e.g. `condition && [[...], :err]`). Only an Array
            # of error pairs is iterated.
            next unless result.is_a?(Array)

            # Apply the scope prefix in place on the rule's returned pairs and collect them
            # directly. Per the `virtual` contract the rule hands back a freshly built Array
            # each call (see `virtual`), so mutating it here is safe and avoids allocating a
            # new pair per error.
            result.each do |sub_result|
              sub_result[0] = scope + sub_result[0]
            end

            errors.push(*result)
          else
            for_checking = data_is_hash ? dig(data, rule.path) : DIG_MISS

            if DIG_MISS.equal?(for_checking)
              errors << [scope + rule.path, :missing] if rule.type == :required
            else
              result = rule.validator.call(for_checking, data, errors, self)

              next if result == true

              errors << [scope + rule.path, result || :format]
            end
          end
        end

        return Result.success if errors.empty?

        Result.new(errors, self)
      end

      # Validates the data and raises when it is invalid
      #
      # @param data [Hash] data for validation
      # @param error_class [Class] error class that should be used when validation fails
      # @param scope [Array<String>] scope of this contract (if any) or empty array if no parent
      #   scope is needed if contract starts from root
      # @return [Boolean] true
      # @raise [StandardError] any error provided in the error_class that inherits from the
      #   standard error
      def validate!(data, error_class, scope: EMPTY_ARRAY)
        result = call(data, scope: scope)

        return true if result.success?

        raise error_class, result.errors
      end

      private

      # Tries to dig for a given key in a hash and returns it with indication whether or not it was possible to find it
      # (dig returns nil and we don't know if it wasn't the digged key value)
      #
      # Uses `Hash#fetch` with the `DIG_MISS` sentinel as the default, which resolves presence and value in a single
      # hash lookup instead of a `key?` check followed by `[]`. `fetch` with a default ignores `default_proc`.
      #
      # @param data [Hash]
      # @param keys [Array<Symbol>]
      # @return [DIG_MISS, Object] found element or DIG_MISS indicating that not found
      def dig(data, keys)
        case keys.length
        when 1
          data.fetch(keys[0], DIG_MISS)
        when 2
          mid = data.fetch(keys[0], DIG_MISS)

          return DIG_MISS if DIG_MISS.equal?(mid)
          return DIG_MISS unless mid.is_a?(Hash)

          mid.fetch(keys[1], DIG_MISS)
        else
          current = data

          keys.each do |nesting|
            return DIG_MISS unless current.is_a?(Hash)

            current = current.fetch(nesting, DIG_MISS)

            return DIG_MISS if DIG_MISS.equal?(current)
          end

          current
        end
      end
    end
  end
end
