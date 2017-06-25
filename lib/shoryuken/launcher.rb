module Shoryuken
  class Launcher
    include Util

    def initialize
      @manager = setup_manager
    end

    def stop(options = {})
      @manager.each do |manager|
        manager.stop(
          shutdown: !options[:shutdown].nil?,
          timeout: Shoryuken.options[:timeout]
        )
      end
    end

    def run
      @manager.each(&:start)
    end

    private

    def setup_manager
      Shoryuken.queues.map do |group, options|
        Shoryuken::Manager.new(
          Shoryuken::Fetcher.new,
          Shoryuken.options[:polling_strategy].new(options[:queues]),
          options[:concurrency]
        )
      end
    end
  end
end
