module Shoryuken
  class Launcher
    include Util

    def initialize
      @managers    = create_managers
      @shutdowning = Concurrent::AtomicBoolean.new(false)
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
      @managers.each do |manager|
        Concurrent::Promise.execute { manager.start }.rescue do |ex|
          log_manager_failure(ex)
          start_soft_shutdown
        end
      end
    end

    def start_soft_shutdown
      Process.kill('USR1', Process.pid) if @shutdowning.make_true
    end

    def log_manager_failure(ex)
      return unless ex

      logger.error { "Manager failed: #{ex.message}" }
      logger.error { ex.backtrace.join("\n") } unless ex.backtrace.nil?
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
      Shoryuken.groups.map do |group, options|
        Shoryuken::Manager.new(
          Shoryuken::Fetcher.new,
          Shoryuken.polling_strategy(group).new(options[:queues]),
          options[:concurrency]
        )
      end
    end
  end
end
