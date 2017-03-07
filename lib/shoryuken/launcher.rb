module Shoryuken
  class Launcher
    include Util

    def initialize
      @manager = Shoryuken::Manager.new(Shoryuken::Fetcher.new,
                                        Shoryuken.options[:polling_strategy].new(Shoryuken.queues))
    end

    def stop(options = {})
      @manager.stop(shutdown: !options[:shutdown].nil?,
                    timeout: Shoryuken.options[:timeout])
    end

    def run
      @manager.start
    end
  end
end
