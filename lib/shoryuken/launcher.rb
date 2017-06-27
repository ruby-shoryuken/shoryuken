module Shoryuken
  class Launcher
    include Util

    def initialize
      @managers = create_managers
    end

    def start
      logger.info { 'Starting' }

      start_callback

      start_managers
    end

    def stop!
      initiate_stop

      executor.shutdown

      return if executor.wait_for_termination(Shoryuken.options[:timeout])

      executor.kill
    end

    def stop
      initiate_stop

      executor.shutdown
      executor.wait_for_termination
    end

    private

    def executor
      Concurrent.global_io_executor
    end

    def start_managers
      @shutdowing = Concurrent::AtomicBoolean.new(false)

      @managers.each do |manager|
        Concurrent::Promise.execute { manager.start }.rescue do |ex|
          if ex
            logger.error { "Manager failed: #{ex.message}" }
            logger.error { ex.backtrace.join("\n") } unless ex.backtrace.nil?
          end

          Process.kill('USR1', Process.pid) if @shutdowing.make_true
        end
      end
    end

    def initiate_stop
      logger.info { 'Shutting down' }

      @managers.each(&:stop)

      stop_callback
    end

    def start_callback
      if (callback = Shoryuken.start_callback)
        logger.debug { 'Calling start_callback' }
        callback.call
      end

      fire_event(:startup)
    end

    def stop_callback
      if (callback = Shoryuken.stop_callback)
        logger.debug { 'Calling stop_callback' }
        callback.call
      end

      fire_event(:shutdown, true)
    end

    def create_managers
      Shoryuken.queues.map do |group, options|
        Shoryuken::Manager.new(
          Shoryuken::Fetcher.new,
          Shoryuken.polling_strategy(group).new(options[:queues]),
          options[:concurrency]
        )
      end
    end
  end
end
