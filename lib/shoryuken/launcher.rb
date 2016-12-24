module Shoryuken
  class Launcher
    include Util

    def initialize
      count = Shoryuken.options.fetch(:concurrency, 25)

      raise(ArgumentError, "Concurrency value #{count} is invalid, it needs to be a positive number") unless count > 0

      manager_count = count / 10
      manager_count = 1 if manager_count < 1

      concurrency = count / manager_count

      @managers = Array.new(manager_count) do
        Shoryuken::Manager.new(concurrency,
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
