module Shoryuken
  class Launcher < Concurrent::Actor::RestartingContext
    include Util

    def initialize
      @manager = Shoryuken::Manager.spawn! name: :manager, link: true
      @fetcher = Shoryuken::Fetcher.spawn! name: :fetcher, link: true, args: [@manager]

      @manager.ask!([:fetcher, @fetcher])
    end

    def stop(options = {})
      watchdog('Launcher#stop') do
        @fetcher.ask!(:terminate!)

        @manager.ask!([:stop, shutdown: !!options[:shutdown], timeout: Shoryuken.options[:timeout]])
        @manager.ask!(:terminate!)
      end
    end

    def run
      watchdog('Launcher#run') do
        @manager.tell(:start)
      end
    end
  end
end
