module Shoryuken
  class Launcher
    include Util

    def initialize
      count = Shoryuken.options.fetch(:concurrency, 25)

      raise(ArgumentError, "Concurrency value #{count} is invalid, it needs to be a positive number") unless count > 0

      @managers = Array.new(count) do
        Shoryuken::Manager.new(1,
                               Shoryuken::Fetcher.new,
                               Shoryuken.options[:polling_strategy].new(Shoryuken.queues))
      end
    end

    def stop(options = {})
      @managers.map do |manager|
        Thread.new { manager.stop(shutdown: !!options[:shutdown], timeout: Shoryuken.options[:timeout]) }
      end.each(&:join)
    end

    def run
      @managers.map do |manager|
        Thread.new { manager.start }
      end.each(&:join)
    end
  end
end
