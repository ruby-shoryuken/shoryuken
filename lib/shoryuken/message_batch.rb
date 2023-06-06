module Shoryuken
  class MessageBatch
    attr_reader :max_size, :timeout, :messages

    def initialize(max_size:, timeout:)
      @max_size = max_size
      @timeout = timeout
      @batch_timeout_start = Time.now
      @messages = []
    end

    def add_message!(message)
      raise ArgumentError, 'Message batch is full' if full?

      @messages << message
    end

    def size
      @messages.size
    end

    def full?
      @messages.size >= @max_size
    end

    def timeout_expired?
      Time.now - @batch_timeout_start > timeout
    end
  end
end
