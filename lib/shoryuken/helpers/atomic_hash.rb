# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread-safe hash implementation using Ruby's Mutex for all operations.
    #
    # This class provides a hash-like interface with thread-safe operations, serving as a
    # drop-in replacement for Concurrent::Hash without requiring external dependencies.
    # The implementation uses a single mutex to protect both read and write operations,
    # ensuring complete thread safety across all Ruby implementations including JRuby.
    #
    # Since hash operations (lookup, assignment) are very fast, the mutex overhead is
    # minimal while providing guaranteed safety and simplicity. This approach avoids
    # the complexity of copy-on-write while maintaining excellent performance for
    # typical usage patterns.
    #
    # @note This implementation uses mutex synchronization for all operations,
    #   ensuring complete thread safety with minimal performance impact.
    #
    # @note All operations are atomic and will never see partial effects from
    #   concurrent operations.
    #
    # @example Basic hash operations
    #   hash = Shoryuken::Helpers::AtomicHash.new
    #   hash['key'] = 'value'
    #   hash['key']           # => 'value'
    #   hash.keys             # => ['key']
    #   hash.clear
    #   hash['key']           # => nil
    #
    # @example Worker registry usage
    #   @workers = Shoryuken::Helpers::AtomicHash.new
    #
    #   # Registration (infrequent writes)
    #   @workers['queue_name'] = WorkerClass
    #
    #   # Lookups (frequent reads)
    #   worker_class = @workers['queue_name']
    #   available_queues = @workers.keys
    #   worker_class = @workers.fetch('queue_name', DefaultWorker)
    #
    # @example Thread-safe concurrent access
    #   hash = Shoryuken::Helpers::AtomicHash.new
    #
    #   # Multiple threads can safely write
    #   Thread.new { hash['key1'] = 'value1' }
    #   Thread.new { hash['key2'] = 'value2' }
    #
    #   # Multiple threads can safely read concurrently
    #   Thread.new { puts hash['key1'] }
    #   Thread.new { puts hash.keys.size }
    class AtomicHash
      # Creates a new empty atomic hash.
      #
      # The hash starts empty and ready to accept key-value pairs through
      # thread-safe operations.
      #
      # @return [AtomicHash] A new empty atomic hash instance
      #
      # @example Creating an empty hash
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash.keys  # => []
      def initialize
        @mutex = Mutex.new
        @hash = {}
      end

      # Returns the value associated with the given key.
      #
      # This operation is thread-safe and will return a consistent value
      # even when called concurrently with write operations.
      #
      # @param key [Object] The key to look up
      # @return [Object, nil] The value associated with the key, or nil if not found
      #
      # @example Reading values
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash['existing'] = 'value'
      #   hash['existing']    # => 'value'
      #   hash['missing']     # => nil
      #
      # @example Works with any key type
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash[:symbol] = 'symbol_value'
      #   hash[42] = 'number_value'
      #   hash[:symbol]  # => 'symbol_value'
      #   hash[42]       # => 'number_value'
      def [](key)
        @mutex.synchronize { @hash[key] }
      end

      # Sets the value for the given key.
      #
      # This is a thread-safe write operation that ensures data integrity
      # when called concurrently with other read or write operations.
      #
      # @param key [Object] The key to set
      # @param value [Object] The value to associate with the key
      # @return [Object] The assigned value
      #
      # @example Setting values
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash['queue1'] = 'Worker1'
      #   hash['queue2'] = 'Worker2'
      #   hash['queue1']  # => 'Worker1'
      #
      # @example Overwriting values
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash['key'] = 'old_value'
      #   hash['key'] = 'new_value'
      #   hash['key']  # => 'new_value'
      def []=(key, value)
        @mutex.synchronize { @hash[key] = value }
      end

      # Removes all key-value pairs from the hash.
      #
      # This is a thread-safe write operation that ensures atomicity
      # when called concurrently with other operations.
      #
      # @return [Hash] An empty hash (for compatibility with standard Hash#clear)
      #
      # @example Clearing all entries
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash['key1'] = 'value1'
      #   hash['key2'] = 'value2'
      #   hash.keys.size  # => 2
      #   hash.clear
      #   hash.keys.size  # => 0
      #   hash['key1']    # => nil
      def clear
        @mutex.synchronize { @hash.clear }
      end

      # Returns an array of all keys in the hash.
      #
      # This operation is thread-safe and will return a consistent snapshot
      # of keys even when called concurrently with write operations.
      #
      # @return [Array] An array containing all keys in the hash
      #
      # @example Getting all keys
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash['queue1'] = 'Worker1'
      #   hash['queue2'] = 'Worker2'
      #   hash.keys  # => ['queue1', 'queue2'] (order not guaranteed)
      #
      # @example Empty hash returns empty array
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash.keys  # => []
      def keys
        @mutex.synchronize { @hash.keys }
      end

      # Returns the value for the given key, or a default value if the key is not found.
      #
      # This operation is thread-safe and will return a consistent value
      # even when called concurrently with write operations.
      #
      # @param key [Object] The key to look up
      # @param default [Object] The value to return if the key is not found
      # @return [Object] The value associated with the key, or the default value
      #
      # @example Fetching with defaults
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash['existing'] = 'found'
      #   hash.fetch('existing', 'default')  # => 'found'
      #   hash.fetch('missing', 'default')   # => 'default'
      #
      # @example Default parameter is optional
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   hash.fetch('missing')  # => nil
      #
      # @example Useful for providing fallback collections
      #   hash = Shoryuken::Helpers::AtomicHash.new
      #   workers = hash.fetch('queue_name', [])  # => [] if not found
      def fetch(key, default = nil)
        @mutex.synchronize { @hash.fetch(key, default) }
      end
    end
  end
end
