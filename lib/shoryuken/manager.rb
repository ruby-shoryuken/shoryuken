module Shoryuken
  class Manager
    include Util

    def initialize(fetcher, polling_strategy)
      @count = Shoryuken.options[:concurrency] || 25
      raise(ArgumentError, "Concurrency value #{@count} is invalid, it needs to be a positive number") unless @count > 0

      @fetcher = fetcher
      @polling_strategy = polling_strategy

      create_processors

      @ready = Concurrent::AtomicFixnum.new(@count)
    end

    def start
      logger.info { 'Starting' }
      @processors.each(&:start)
    end

    def stop(options = {})
      if (callback = Shoryuken.stop_callback)
        logger.info { 'Calling Shoryuken.on_stop block' }
        callback.call
      end

      fire_event(:shutdown, true)

      logger.info { "Shutting down workers" }

      if options[:shutdown]
        hard_shutdown_in(options[:timeout])
      else
        soft_shutdown
      end
    end

    def create_processors
      @processors = (1..@count).map do
        # fix this initialisation. we should creating new copies instead of calling .dup
        Processor.new(@fetcher.dup, @polling_strategy.dup)
      end
    end

    private

    def soft_shutdown
      @processors.each(&:terminate)
    end

    def hard_shutdown_in(delay)
      logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }

      soft_shutdown

      wait_until = Time.now + delay
      while Time.now < wait_until && has_alive_processors?
        sleep(0.1)
      end

      @processors.each(&:kill)
    end

    def has_alive_processors?
      @processors.any?(&:alive?)
    end
  end
end
