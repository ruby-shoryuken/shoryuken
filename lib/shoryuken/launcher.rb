# frozen_string_literal: true

module Shoryuken
  # Launches and coordinates Shoryuken's message processing managers.
  # Handles the lifecycle of the processing system including startup, shutdown, and health checks.
  class Launcher
    include Util

    # Initializes a new Launcher with managers for each processing group
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

    # Starts the message processing system
    #
    # @return [void]
    def start
      logger.info { 'Starting' }

      start_callback
      start_managers
    end

    # Forces an immediate stop of all processing
    #
    # @return [void]
    def stop!
      @stopping = true
      initiate_stop

      # Don't await here so the timeout below is not delayed
      stop_new_dispatching

      shutdown_executor

      fire_event(:stopped)
    end

    # Gracefully stops all processing, waiting for in-flight messages
    #
    # @return [void]
    def stop
      @stopping = true
      fire_event(:quiet, true)

      initiate_stop

      stop_new_dispatching
      await_dispatching_in_progress

      shutdown_executor

      fire_event(:stopped)
    end

    # Checks if all processing groups are healthy
    #
    # @return [Boolean] true if all groups are running normally
    def healthy?
      Shoryuken.groups.keys.all? do |group|
        manager = @managers.find { |m| m.group == group }
        manager && manager.running?
      end
    end

    private

    # Stops all managers from dispatching new messages
    #
    # @return [void]
    def stop_new_dispatching
      @managers.each(&:stop_new_dispatching)
    end

    # Waits for any in-progress dispatching to complete
    #
    # @return [void]
    def await_dispatching_in_progress
      @managers.each(&:await_dispatching_in_progress)
    end

    # Shuts the executor down, giving in-flight workers up to the configured
    # timeout to finish before force-killing them so the process can exit.
    # Used by both the graceful ({#stop}) and immediate ({#stop!}) shutdowns:
    # a graceful stop still waits for workers, but must not block forever on a
    # hung one.
    #
    # @return [void]
    def shutdown_executor
      executor.shutdown
      executor.kill unless executor.wait_for_termination(Shoryuken.options[:timeout])
    end

    # Returns the executor for running async operations
    #
    # Owns a dedicated executor rather than borrowing Concurrent.global_io_executor:
    # {#stop} and {#stop!} shut down and kill this executor, and destroying the
    # process-global pool would break anything else relying on it (including
    # Shoryuken's own ShoryukenConcurrentSendAdapter) and prevent a fresh launcher
    # from starting in the same process.
    #
    # @return [Concurrent::ExecutorService] the executor service
    def executor
      @_executor ||= Shoryuken.launcher_executor || Concurrent::CachedThreadPool.new(auto_terminate: true)
    end

    # Starts all managers in parallel futures
    #
    # @return [void]
    def start_managers
      @managers.each do |manager|
        Concurrent::Future.execute { manager.start }
      end
    end

    # Initiates the stop sequence
    #
    # @return [void]
    def initiate_stop
      logger.info { 'Shutting down' }

      stop_callback
    end

    # Executes the start callback and fires startup event
    #
    # @return [void]
    def start_callback
      Shoryuken.start_callback&.call
      fire_event(:startup)
    end

    # Executes the stop callback and fires shutdown event
    #
    # @return [void]
    def stop_callback
      Shoryuken.stop_callback&.call
      fire_event(:shutdown, true)
    end

    # Creates managers for each configured processing group
    #
    # @return [Array<Shoryuken::Manager>] the created managers
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
