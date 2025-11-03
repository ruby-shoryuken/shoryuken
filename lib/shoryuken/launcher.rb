# frozen_string_literal: true

module Shoryuken
  class Launcher
    include Util

    def initialize
      @managers = create_managers
      @stopping = false
    end

    # Indicates whether the launcher is in the process of stopping.
    #
    # This flag is set to true when either {#stop} or {#stop!} is called,
    # and is used by ActiveJob adapters to signal jobs that they should
    # checkpoint and prepare for graceful shutdown.
    #
    # @return [Boolean] true if stopping, false otherwise
    def stopping?
      @stopping
    end

    def start
      logger.info { 'Starting' }

      start_callback
      start_managers
    end

    def stop!
      @stopping = true
      initiate_stop

      # Don't await here so the timeout below is not delayed
      stop_new_dispatching

      executor.shutdown
      executor.kill unless executor.wait_for_termination(Shoryuken.options[:timeout])

      fire_event(:stopped)
    end

    def stop
      @stopping = true
      fire_event(:quiet, true)

      initiate_stop

      stop_new_dispatching
      await_dispatching_in_progress

      executor.shutdown
      executor.wait_for_termination

      fire_event(:stopped)
    end

    def healthy?
      Shoryuken.groups.keys.all? do |group|
        manager = @managers.find { |m| m.group == group }
        manager && manager.running?
      end
    end

    private

    def stop_new_dispatching
      @managers.each(&:stop_new_dispatching)
    end

    def await_dispatching_in_progress
      @managers.each(&:await_dispatching_in_progress)
    end

    def executor
      @_executor ||= Shoryuken.launcher_executor || Concurrent.global_io_executor
    end

    def start_managers
      @managers.each do |manager|
        Concurrent::Future.execute { manager.start }
      end
    end

    def initiate_stop
      logger.info { 'Shutting down' }

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
          group,
          Shoryuken::Fetcher.new(group),
          Shoryuken.polling_strategy(group).new(options[:queues], Shoryuken.delay(group)),
          options[:concurrency],
          executor
        )
      end
    end
  end
end
