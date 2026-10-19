# frozen_string_literal: true

# Thread-safe data collector for integration tests
# Inspired by Karafka's DataCollector pattern
# Usage: DT[:key] << value, DT[:key].size, DT.clear
class DataCollector
  include Singleton

  MUTEX = Mutex.new
  private_constant :MUTEX

  attr_reader :queues, :data

  class << self
    def queue
      instance.queue
    end

    def queues
      instance.queues
    end

    def data
      instance.data
    end

    def [](key)
      MUTEX.synchronize { data[key] }
    end

    def []=(key, value)
      MUTEX.synchronize { data[key] = value }
    end

    def uuids(amount)
      Array.new(amount) { uuid }
    end

    def uuid
      "it-#{SecureRandom.uuid[0, 8]}"
    end

    def clear
      MUTEX.synchronize { instance.clear }
    end

    def key?(key)
      instance.data.key?(key)
    end
  end

  def initialize
    @mutex = Mutex.new
    @queues = Array.new(100) { "it-#{SecureRandom.hex(6)}" }
    @data = Hash.new do |hash, key|
      @mutex.synchronize do
        break hash[key] if hash.key?(key)

        hash[key] = []
      end
    end
  end

  def queue
    queues.first
  end

  def clear
    @mutex.synchronize do
      @queues.clear
      @queues.concat(Array.new(100) { "it-#{SecureRandom.hex(6)}" })
      @data.clear
    end
  end
end

# Short alias for DataCollector
DT = DataCollector
