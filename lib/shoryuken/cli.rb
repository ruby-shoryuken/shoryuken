$stdout.sync = true

require 'singleton'
require 'optparse'
require 'erb'

require 'shoryuken'

module Shoryuken
  # See: https://github.com/mperham/sidekiq/blob/33f5d6b2b6c0dfaab11e5d39688cab7ebadc83ae/lib/sidekiq/cli.rb#L20
  class Shutdown < Interrupt; end

  class CLI
    include Util
    include Singleton

    attr_accessor :launcher

    def run(args)
      self_read, self_write = IO.pipe

      %w[INT TERM USR1 USR2 TTIN].each do |sig|
        begin
          trap sig do
            self_write.puts(sig)
          end
        rescue ArgumentError
          puts "Signal #{sig} not supported"
        end
      end

      options = parse_cli_args(args)

      EnvironmentLoader.load(options)

      daemonize
      write_pid
      load_celluloid

      require 'shoryuken/launcher'
      @launcher = Shoryuken::Launcher.new

      if callback = Shoryuken.start_callback
        logger.info "Calling Shoryuken.on_start block"
        callback.call
      end

      begin
        launcher.run

        while readable_io = IO.select([self_read])
          signal = readable_io.first[0].gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        launcher.stop(shutdown: true)
        exit 0
      end
    end

    private

    def load_celluloid
      raise "Celluloid cannot be required until here, or it will break Shoryuken's daemonization" if defined?(::Celluloid) && Shoryuken.options[:daemon]

      # Celluloid can't be loaded until after we've daemonized
      # because it spins up threads and creates locks which get
      # into a very bad state if forked.
      require 'celluloid/autostart'
      Celluloid.logger = (Shoryuken.options[:verbose] ? Shoryuken.logger : nil)

      require 'shoryuken/manager'
    end

    def daemonize
      return unless Shoryuken.options[:daemon]

      raise ArgumentError, "You really should set a logfile if you're going to daemonize" unless Shoryuken.options[:logfile]

      files_to_reopen = []
      ObjectSpace.each_object(File) do |file|
        files_to_reopen << file unless file.closed?
      end

      Process.daemon(true, true)

      files_to_reopen.each do |file|
        begin
          file.reopen file.path, "a+"
          file.sync = true
        rescue ::Exception
        end
      end

      [$stdout, $stderr].each do |io|
        File.open(Shoryuken.options[:logfile], 'ab') do |f|
          io.reopen(f)
        end
        io.sync = true
      end
      $stdin.reopen('/dev/null')
    end

    def write_pid
      if path = Shoryuken.options[:pidfile]
        File.open(path, 'w') do |f|
          f.puts Process.pid
        end
      end
    end

    def parse_cli_args(argv)
      opts = { queues: [] }

      @parser = OptionParser.new do |o|
        o.on '-c', '--concurrency INT', 'Processor threads to use' do |arg|
          opts[:concurrency] = Integer(arg)
        end

        o.on '-d', '--daemon', 'Daemonize process' do |arg|
          opts[:daemon] = arg
        end

        o.on '-q', '--queue QUEUE[,WEIGHT]...', 'Queues to process with optional weights' do |arg|
          queue, weight = arg.split(',')
          opts[:queues] << [queue, weight]
        end

        o.on '-r', '--require [PATH|DIR]', 'Location of the worker' do |arg|
          opts[:require] = arg
        end

        o.on '-C', '--config PATH', 'Path to YAML config file' do |arg|
          opts[:config_file] = arg
        end

        o.on '-R', '--rails', 'Load Rails' do |arg|
          opts[:rails] = arg
        end

        o.on '-L', '--logfile PATH', 'Path to writable logfile' do |arg|
          opts[:logfile] = arg
        end

        o.on '-P', '--pidfile PATH', 'Path to pidfile' do |arg|
          opts[:pidfile] = arg
        end

        o.on '-v', '--verbose', 'Print more verbose output' do |arg|
          opts[:verbose] = arg
        end

        o.on '-V', '--version', 'Print version and exit' do |arg|
          puts "Shoryuken #{Shoryuken::VERSION}"
          exit 0
        end
      end

      @parser.banner = 'shoryuken [options]'
      @parser.on_tail '-h', '--help', 'Show help' do
        logger.info @parser
        exit 1
      end
      @parser.parse!(argv)
      opts
    end

    def handle_signal(sig)
      logger.info "Got #{sig} signal"

      case sig
      when 'USR1'
        logger.info "Received USR1, will soft shutdown down"

        launcher.stop

        exit 0
      when 'TTIN'
        Thread.list.each do |thread|
          logger.info "Thread TID-#{thread.object_id.to_s(36)} #{thread['label']}"
          if thread.backtrace
            logger.info thread.backtrace.join("\n")
          else
            logger.info "<no backtrace available>"
          end
        end

        ready  = launcher.manager.instance_variable_get(:@ready).size
        busy   = launcher.manager.instance_variable_get(:@busy).size
        queues = launcher.manager.instance_variable_get(:@queues)

        logger.info "Ready: #{ready}, Busy: #{busy}, Active Queues: #{unparse_queues(queues)}"
      else
        logger.info "Received #{sig}, will shutdown down"

        raise Interrupt
      end
    end
  end
end
