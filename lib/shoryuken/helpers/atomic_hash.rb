# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread-safe hash implementation using Ruby's Mutex for write operations.
    #
    # This class provides a hash-like interface with thread-safe operations, serving as a
    # drop-in replacement for Concurrent::Hash without requiring external dependencies.
    # The implementation uses a selective synchronization approach: read operations can
    # proceed concurrently for maximum performance, while write operations are protected
    # by a mutex to ensure data integrity.
    #
    # This design is particularly important for JRuby compatibility, where true parallelism
    # means that unsynchronized hash operations can lead to data corruption or infinite loops.
    # The read-heavy optimization makes it ideal for scenarios like worker registries where
    # lookups are frequent but modifications are rare.
    #
    # @note This implementation prioritizes read performance over write performance,
    #   making it optimal for read-heavy workloads with infrequent updates.
    #
    # @note While reads are concurrent, they are not isolated from writes. A read
    #   operation may see partial effects of a concurrent write operation.
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
      # This is a concurrent read operation that does not acquire the mutex,
      # allowing multiple threads to read simultaneously for optimal performance.
      # Returns nil if the key is not found.
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
        @hash[key]
      end

      # Sets the value for the given key.
      #
      # This is a thread-safe write operation that acquires the mutex to ensure
      # data integrity. Multiple concurrent write operations will be serialized
      # to prevent data corruption.
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
      # This is a thread-safe write operation that acquires the mutex to ensure
      # the clear operation is atomic. After calling this method, the hash will
      # be empty.
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
      # This is a concurrent read operation that does not acquire the mutex,
      # allowing multiple threads to enumerate keys simultaneously. The returned
      # array is a snapshot of keys at the time of the call.
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
        @hash.keys
      end

      # Returns the value for the given key, or a default value if the key is not found.
      #
      # This is a concurrent read operation that does not acquire the mutex,
      # allowing optimal performance for lookups with fallback values.
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
        @hash.fetch(key, default)
      end
    end
  end
end
