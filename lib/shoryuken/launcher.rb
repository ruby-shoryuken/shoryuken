module Shoryuken
  class Launcher
    include Util

    def initialize
      @managers = create_managers
    end

    def start
      logger.info { 'Starting' }

      start_callback

      @managers.each do |manager|
        Concurrent::Promise.execute { manager.start }.rescue do |ex|
          Thread.main.raise(ex)
        end
      end
    end

    def stop!
      initiate_stop

      logger.info { 'Hard shutting down' }

      Concurrent.global_io_executor.shutdown

      return if Concurrent.global_io_executor.wait_for_termination(Shoryuken.options[:timeout])

      Concurrent.global_io_executor.kill
    end

    def stop
      initiate_stop

      logger.info { 'Shutting down' }

      Concurrent.global_io_executor.shutdown
      Concurrent.global_io_executor.wait_for_termination
    end

    private

    def initiate_stop
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
          Shoryuken.options[:polling_strategy].new(options[:queues]),
          options[:concurrency]
        )
      end
    end
  end
end
