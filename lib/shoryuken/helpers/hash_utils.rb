# frozen_string_literal: true

module Shoryuken
  module Helpers
    # Utility methods for hash manipulation.
    #
    # This module provides helper methods for common hash operations that were
    # previously implemented as core class extensions. By using a dedicated
    # helper module, we avoid polluting the global namespace while maintaining
    # the same functionality.
    #
    # @example Basic usage
    #   hash = { 'key1' => 'value1', 'key2' => { 'nested' => 'value2' } }
    #   symbolized = Shoryuken::Helpers::HashUtils.deep_symbolize_keys(hash)
    #   # => { key1: 'value1', key2: { nested: 'value2' } }
    module HashUtils
      class << self
        # Recursively converts hash keys to symbols.
        #
        # This method traverses a hash structure and converts all string keys
        # to symbols, including nested hashes. Non-hash values are left unchanged.
        # This is useful for normalizing configuration data loaded from YAML files.
        #
        # @param hash [Hash, Object] The hash to convert, or any other object
        # @return [Hash, Object] Hash with symbolized keys, or the original object if not a hash
        #
        # @example Converting a simple hash
        #   hash = { 'key1' => 'value1', 'key2' => 'value2' }
        #   HashUtils.deep_symbolize_keys(hash)
        #   # => { key1: 'value1', key2: 'value2' }
        #
        # @example Converting a nested hash
        #   hash = { 'config' => { 'timeout' => 30, 'retries' => 3 } }
        #   HashUtils.deep_symbolize_keys(hash)
        #   # => { config: { timeout: 30, retries: 3 } }
        #
        # @example Handling non-hash input gracefully
        #   HashUtils.deep_symbolize_keys('not a hash')
        #   # => 'not a hash'
        #
        # @example Mixed value types
        #   hash = { 'string' => 'value', 'number' => 42, 'nested' => { 'bool' => true } }
        #   HashUtils.deep_symbolize_keys(hash)
        #   # => { string: 'value', number: 42, nested: { bool: true } }
        def deep_symbolize_keys(hash)
          return hash unless hash.is_a?(Hash)

          hash.each_with_object({}) do |(key, value), result|
            symbol_key = (key.to_sym rescue key) || key
            result[symbol_key] = value.is_a?(Hash) ? deep_symbolize_keys(value) : value
          end
        end
      end
    end
  end
end
