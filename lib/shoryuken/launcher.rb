module Shoryuken
  class Launcher
    include Util

    def initialize
      @manager = Shoryuken::Manager.new(Shoryuken::Fetcher.new,
                                        Shoryuken.options[:polling_strategy].new(Shoryuken.queues))
    end

    def stop(options = {})
      watchdog('Launcher#stop') do
        @manager.stop(shutdown: !!options[:shutdown],
                      timeout: Shoryuken.options[:timeout])
      end
    end

    def run
      watchdog('Launcher#run') do
        @manager.start
      end
    end
  end
end
