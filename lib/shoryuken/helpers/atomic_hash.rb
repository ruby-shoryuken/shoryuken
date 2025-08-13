# frozen_string_literal: true

module Shoryuken
  module Helpers
    # A thread-safe hash implementation using Ruby's Mutex for write operations.
    # Drop-in replacement for Concurrent::Hash without external dependencies.
    # Allows concurrent reads while protecting writes for JRuby compatibility.
    class AtomicHash
      def initialize
        @mutex = Mutex.new
        @hash = {}
      end

      # Get value by key (concurrent read)
      def [](key)
        @hash[key]
      end

      # Set value by key (mutex-protected write)
      def []=(key, value)
        @mutex.synchronize { @hash[key] = value }
      end

      # Clear all entries (mutex-protected write)
      def clear
        @mutex.synchronize { @hash.clear }
      end

      # Get all keys (concurrent read)
      def keys
        @hash.keys
      end

      # Fetch with default value (concurrent read)
      def fetch(key, default = nil)
        @hash.fetch(key, default)
      end
    end
  end
end
