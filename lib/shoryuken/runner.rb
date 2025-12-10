# frozen_string_literal: true

$stdout.sync = true

require 'singleton'
require 'optparse'
require 'erb'

require 'shoryuken'

module Shoryuken
  # Exception raised to trigger shutdown
  # @see https://github.com/mperham/sidekiq/blob/33f5d6b2b6c0dfaab11e5d39688cab7ebadc83ae/lib/sidekiq/cli.rb#L20
  class Shutdown < Interrupt; end

  # Runs the Shoryuken server process.
  # Handles signal trapping, daemonization, and lifecycle management.
  class Runner
    include Util
    include Singleton

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
      self_read, self_write = IO.pipe

      %w[INT TERM USR1 TSTP TTIN].each do |sig|
        trap sig do
          self_write.puts(sig)
        end
      rescue ArgumentError
        puts "Signal #{sig} not supported"
      end

      loader = EnvironmentLoader.setup_options(options)

      daemonize(Shoryuken.options)
      write_pid(Shoryuken.options)

      loader.load

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
      (@launcher && @launcher.healthy?) || false
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
      rescue ::Exception
      end

      [$stdout, $stderr].each do |io|
        File.open(options[:logfile], 'ab') do |f|
          io.reopen(f)
        end
        io.sync = true
      end
      $stdin.reopen('/dev/null')
    end

    # Writes the process ID to a file
    #
    # @param options [Hash] options containing the pidfile path
    # @option options [String] :pidfile path to write the PID file
    # @return [void]
    def write_pid(options)
      return unless (path = options[:pidfile])

      File.open(path, 'w') { |f| f.puts(Process.pid) }
    end

    # Executes a soft shutdown on USR1 signal
    #
    # @return [void]
    def execute_soft_shutdown
      logger.info { 'Received USR1, will soft shutdown' }

      @launcher.stop
      exit 0
    end

    # Executes a terminal stop on TSTP signal
    #
    # @return [void]
    def execute_terminal_stop
      logger.info { 'Received TSTP, will stop accepting new work' }

      @launcher.stop
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
      when 'TERM', 'INT'
        logger.info { "Received #{sig}, will shutdown" }

        raise Interrupt
      end
    end
  end
end
