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
    # This flag is set to true when either {#stop} or {#stop!} is called, and is used by ActiveJob adapters to signal jobs
    # that they should checkpoint and prepare for graceful shutdown.
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

      deadline = shutdown_deadline
      shutdown_executor

      drain_pending_active_job_sends(deadline)

      fire_event(:stopped)
    end

    # Gracefully stops all processing, waiting for in-flight messages
    #
    # @return [void]
    def stop
      @stopping = true
      fire_event(:quiet, true)

      initiate_stop

      signalled_managers = stop_new_dispatching
      await_dispatching_in_progress(signalled_managers)

      deadline = shutdown_deadline
      shutdown_executor

      drain_pending_active_job_sends(deadline)

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
    # @return [Array<Shoryuken::Manager>] the managers that were signalled without an error
    def stop_new_dispatching
      @managers.select do |manager|
        shutdown_step(:stop_new_dispatching) do
          manager.stop_new_dispatching
          true
        end
      end
    end

    # Waits for any in-progress dispatching to complete. Only managers that were signalled are awaited: a manager whose
    # stop_new_dispatching raised may never release its waiters, and a rescue cannot unblock that wait.
    #
    # @param managers [Array<Shoryuken::Manager>] the managers to wait for
    # @return [void]
    def await_dispatching_in_progress(managers)
      managers.each do |manager|
        shutdown_step(:await_dispatching_in_progress) { manager.await_dispatching_in_progress }
      end
    end

    # Shuts the executor down, giving in-flight workers up to the configured timeout to finish before force-killing them so
    # the process can exit. Used by both the graceful ({#stop}) and immediate ({#stop!}) shutdowns: a graceful stop still
    # waits for workers, but must not block forever on a hung one.
    #
    # @return [void]
    def shutdown_executor
      shutdown_step(:shutdown_executor) do
        executor.shutdown
        executor.kill unless executor.wait_for_termination(Shoryuken.options[:timeout])
      end
    end

    # Runs a single shutdown step, logging instead of raising its error so that one failing step cannot skip the
    # remaining ones (most importantly the executor shutdown)
    #
    # @param step [Symbol] name of the step, used in the log message
    # @yield the shutdown step to run
    # @return [Object, nil] the block's result, or nil if it raised
    def shutdown_step(step)
      yield
    rescue => e
      logger.error { "Shutdown step '#{step}' failed: #{e.class.name}: #{e.message}" }
      logger.debug { e.backtrace.join("\n") } unless e.backtrace.nil?
      nil
    end

    # Returns the monotonic time by which the executor shutdown and the send drain must both be done, so together they
    # stay within the configured timeout. A nil timeout means no deadline, as for the executor shutdown.
    #
    # @return [Float, nil] the deadline, in monotonic seconds, or nil when no timeout is configured
    def shutdown_deadline
      timeout = Shoryuken.options[:timeout]
      return if timeout.nil?

      Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    end

    # Drains in-flight asynchronous ActiveJob sends, so jobs enqueued just before shutdown (e.g. by a worker) reach SQS
    # instead of being dropped when the process exits. Covers the adapter of every loaded job class that supports
    # draining (i.e. ShoryukenConcurrentSendAdapter), including adapters set on a single job class.
    #
    # @param deadline [Float, nil] monotonic time by which the drain must finish, or nil to wait without a deadline
    # @return [void]
    def drain_pending_active_job_sends(deadline)
      return unless defined?(::ActiveJob::Base)

      shutdown_step(:drain_pending_active_job_sends) do
        adapters = [::ActiveJob::Base, *::ActiveJob::Base.descendants].map(&:queue_adapter).uniq
        adapters.select! { |adapter| adapter.respond_to?(:wait_for_pending_sends) }
        next if adapters.empty?

        logger.info { 'Draining in-flight ActiveJob sends' }

        drained = adapters.map do |adapter|
          remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max if deadline
          adapter.wait_for_pending_sends(remaining)
        end

        logger.warn { 'Timed out draining in-flight ActiveJob sends; some may not have been delivered' } unless drained.all?
      end
    end

    # Returns the executor for running async operations
    #
    # Owns a dedicated executor rather than borrowing Concurrent.global_io_executor: {#stop} and {#stop!} shut down and kill
    # this executor, and destroying the process-global pool would break anything else relying on it (including Shoryuken's
    # own ShoryukenConcurrentSendAdapter) and prevent a fresh launcher from starting in the same process.
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
      if (callback = Shoryuken.start_callback)
        logger.debug { 'Calling start_callback' }
        callback.call
      end

      fire_event(:startup)
    end

    # Executes the stop callback and fires shutdown event
    #
    # @return [void]
    def stop_callback
      if (callback = Shoryuken.stop_callback)
        logger.debug { 'Calling stop_callback' }
        shutdown_step(:stop_callback) { callback.call }
      end

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
