module Shoryuken
  class Launcher
    include Celluloid
    include Util

    trap_exit :actor_died

    attr_accessor :manager

    def initialize
      @condvar = Celluloid::Condition.new
      @manager = Shoryuken::Manager.new_link(@condvar)
      @fetcher = Shoryuken::Fetcher.new_link(manager)

      @done = false

      manager.fetcher = @fetcher
    end

    def stop(options = {})
      watchdog('Launcher#stop') do
        @done = true
        @fetcher.terminate if @fetcher.alive?

        manager.async.stop(shutdown: !!options[:shutdown], timeout: Shoryuken.options[:timeout])
        @condvar.wait
        manager.terminate
      end
    end

    def run
      watchdog('Launcher#run') do
        manager.async.start
      end
    end

    def actor_died(actor, reason)
      return if @done
      logger.warn { 'Shoryuken died due to the following error, cannot recover, process exiting' }
      exit 1
    end
  end
end
