# frozen_string_literal: true

$stdout.sync = true

require 'singleton'
require 'erb'

require 'shoryuken'

module Shoryuken
  # Runs the Shoryuken server process.
  # Handles signal trapping, daemonization, and lifecycle management.
  class Runner
    include Util
    include Singleton

    # Written to the signal pipe by the graceful stop thread when it ends
    GRACEFUL_STOP_DONE = 'GRACEFUL_STOP_DONE'
    private_constant :GRACEFUL_STOP_DONE

    # @return [Shoryuken::Launcher, nil] the launcher instance, or nil if not yet initialized
    attr_reader :launcher

    # Runs the Shoryuken server with the given options
    #
    # @param options [Hash] runtime configuration options
    # @option options [Boolean] :daemon whether to daemonize the process
    # @option options [String] :pidfile path to the PID file
    # @option options [String] :logfile path to the log file
    # @option options [String] :config_file path to the configuration file
    # @return [void]
    def run(options)
      self_read, @self_write = IO.pipe
      @graceful_stop = nil
      @graceful_stop_done = false
      @exit_after_graceful_stop = false

      %w[INT TERM USR1 TSTP TTIN].each do |sig|
        trap sig do
          @self_write.puts(sig)
        end
      rescue ArgumentError
        puts "Signal #{sig} not supported"
      end

      loader = EnvironmentLoader.setup_options(options)

      # A daemon checks what it can before it forks, so these errors reach the launching process. Required files may
      # start threads that the fork would kill (#219), so it loads before the fork only when there is nothing to require.
      load_before_fork = Shoryuken.options[:daemon] && !Shoryuken.options[:require]
      loader.validate_daemon_options if Shoryuken.options[:daemon]
      loader.load if load_before_fork

      daemonize(Shoryuken.options)
      write_pid(Shoryuken.options)

      loader.load unless load_before_fork

      initialize_concurrent_logger

      @launcher = Shoryuken::Launcher.new

      begin
        @launcher.start

        while (readable_io = IO.select([self_read]))
          signal = readable_io.first[0].gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        @launcher.stop!
        exit 0
      end
    end

    # Checks if the server is healthy
    #
    # @return [Boolean] true if the launcher is running and healthy
    def healthy?
      @launcher&.healthy? || false
    end

    private

    # Initializes the Concurrent Ruby logger
    #
    # @return [void]
    def initialize_concurrent_logger
      return unless Shoryuken.logger

      Concurrent.global_logger = lambda do |level, progname, msg = nil, &block|
        Shoryuken.logger.log(level, msg, progname, &block)
      end
    end

    # Daemonizes the process
    #
    # @param options [Hash] options containing daemon and logfile settings
    # @option options [Boolean] :daemon whether to daemonize
    # @option options [String] :logfile path to the log file for daemon output
    # @return [void]
    def daemonize(options)
      return unless options[:daemon]

      files_to_reopen = []
      ObjectSpace.each_object(File) do |file|
        files_to_reopen << file unless file.closed?
      end

      Process.daemon(true, true)

      files_to_reopen.each do |file|
        file.reopen file.path, 'a+'
        file.sync = true
      rescue ::Exception # rubocop:disable Lint/RescueException
      end

      [$stdout, $stderr].each do |io|
        File.open(options[:logfile], 'ab') do |f|
          io.reopen(f)
        end
        io.sync = true
      end
      $stdin.reopen('/dev/null')
    end

    # Writes the process ID to a file and removes the file at exit when it still holds that ID
    #
    # @param options [Hash] options containing the pidfile path
    # @option options [String] :pidfile path to write the PID file
    # @return [void]
    def write_pid(options)
      return unless (path = options[:pidfile])

      path = File.expand_path(path)
      File.open(path, 'w') { |f| f.puts(Process.pid) }

      # A process forked from this one inherits the hook, and a restarted one may already own the file
      at_exit { remove_pid(path) }
    end

    # Removes the pidfile when it holds the ID of this process
    #
    # @param path [String] path of the PID file
    # @return [void]
    def remove_pid(path)
      File.delete(path) if File.read(path).to_i == Process.pid
    rescue SystemCallError
      nil
    end

    # Executes a soft shutdown on USR1 signal. Exits with status 1 when a fatal dispatch error sent the signal, so a
    # process supervisor sees a crash.
    #
    # @return [void]
    def execute_soft_shutdown
      logger.info { 'Received USR1, will soft shutdown' }

      @exit_after_graceful_stop = true
      start_graceful_stop
    end

    # Executes a terminal stop on TSTP signal
    #
    # @return [void]
    def execute_terminal_stop
      logger.info { 'Received TSTP, will stop accepting new work' }

      start_graceful_stop
    end

    # Runs the graceful stop in a thread, so that a TERM or INT that arrives during it is still handled at once
    #
    # @return [void]
    def start_graceful_stop
      return finish_graceful_stop if @graceful_stop_done

      @graceful_stop ||= Thread.new do
        Thread.current.report_on_exception = false
        @launcher.stop
      ensure
        @self_write.puts(GRACEFUL_STOP_DONE)
      end
    end

    # Runs on the main thread once the graceful stop has ended. Raises its error, and exits after a soft shutdown.
    #
    # @return [void]
    def finish_graceful_stop
      @graceful_stop_done = true
      @graceful_stop.value

      exit(@launcher.failed? ? 1 : 0) if @exit_after_graceful_stop
    end

    # Prints backtraces of all threads
    #
    # @return [void]
    def print_threads_backtrace
      Thread.list.each do |thread|
        logger.info { "Thread TID-#{thread.object_id.to_s(36)} #{thread['label']}" }
        if thread.backtrace
          logger.info { thread.backtrace.join("\n") }
        else
          logger.info { '<no backtrace available>' }
        end
      end
    end

    # Handles incoming signals
    #
    # @param sig [String] the signal name
    # @return [void]
    # @raise [Interrupt] on TERM or INT signals
    def handle_signal(sig)
      logger.debug "Got #{sig} signal"

      case sig
      when 'USR1' then execute_soft_shutdown
      when 'TTIN' then print_threads_backtrace
      when 'TSTP' then execute_terminal_stop
      when GRACEFUL_STOP_DONE then finish_graceful_stop
      when 'TERM', 'INT'
        logger.info { "Received #{sig}, will shutdown" }

        raise Interrupt
      end
    end
  end
end
