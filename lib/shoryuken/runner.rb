$stdout.sync = true

require 'singleton'
require 'optparse'
require 'erb'

require 'shoryuken'

module Shoryuken
  # rubocop:disable Lint/InheritException
  # See: https://github.com/mperham/sidekiq/blob/33f5d6b2b6c0dfaab11e5d39688cab7ebadc83ae/lib/sidekiq/cli.rb#L20
  class Shutdown < Interrupt; end

  class Runner
    include Util
    include Singleton

    def run(options)
      self_read, self_write = IO.pipe

      %w[INT TERM USR1 TSTP TTIN].each do |sig|
        begin
          trap sig do
            self_write.puts(sig)
          end
        rescue ArgumentError
          puts "Signal #{sig} not supported"
        end
      end

      loader = EnvironmentLoader.setup_options(options)

      # When cli args exist, override options in config file
      Shoryuken.options.merge!(options)

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

    private

    def initialize_concurrent_logger
      return unless Shoryuken.logger

      Concurrent.global_logger = lambda do |level, progname, msg = nil, &block|
        Shoryuken.logger.log(level, msg, progname, &block)
      end
    end

    def daemonize(options)
      return unless options[:daemon]

      files_to_reopen = []
      ObjectSpace.each_object(File) do |file|
        files_to_reopen << file unless file.closed?
      end

      Process.daemon(true, true)

      files_to_reopen.each do |file|
        begin
          file.reopen file.path, 'a+'
          file.sync = true
        rescue ::Exception
        end
      end

      [$stdout, $stderr].each do |io|
        File.open(options[:logfile], 'ab') do |f|
          io.reopen(f)
        end
        io.sync = true
      end
      $stdin.reopen('/dev/null')
    end

    def write_pid(options)
      return unless (path = options[:pidfile])

      File.open(path, 'w') { |f| f.puts(Process.pid) }
    end

    def execute_soft_shutdown
      logger.info { 'Received USR1, will soft shutdown down' }

      @launcher.stop
      exit 0
    end

    def execute_terminal_stop
      logger.info { 'Received TSTP, will stop accepting new work' }

      @launcher.stop
    end

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
