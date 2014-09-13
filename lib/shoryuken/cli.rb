$stdout.sync = true

require 'singleton'
require 'optparse'
require 'erb'

module Shoryuken
  class CLI
    include Util
    include Singleton

    def run(args)
      self_read, self_write = IO.pipe

      %w(INT TERM USR1 USR2 TTIN).each do |sig|
        trap sig do
          self_write.puts(sig)
        end
      end

      setup_options(args)
      initialize_logger
      initialize_aws
      require_workers

      launcher = Shoryuken::Launcher.new(Shoryuken.options)

      begin
        launcher.run

        while readable_io = IO.select([self_read])
          signal = readable_io.first[0].gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        logger.info 'Shutting down'
        launcher.stop
        exit(0)
      end


    end

    private

    def parse_options(argv)
      opts = {}

      @parser = OptionParser.new do |o|
        o.on '-r', '--require [PATH|DIR]', 'Location of workers or files to require' do |arg|
          opts[:require] = arg
        end

        o.on '-C', '--config PATH', 'path to YAML config file' do |arg|
          opts[:config_file] = arg
        end

        o.on '-L', '--logfile PATH', 'path to writable logfile' do |arg|
          opts[:logfile] = arg
        end

        # o.on '-P', '--pidfile PATH', "path to pidfile" do |arg|
        # opts[:pidfile] = arg
        # end

        o.on '-v', '--verbose', 'Print more verbose output' do |arg|
          opts[:verbose] = arg
        end

        o.on '-V', '--version', 'Print version and exit' do |arg|
          puts "Shoryuken #{Shoryuken::VERSION}"
          exit(0)
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
      Shoryuken.logger.info "Got #{sig} signal"

      raise Interrupt
    end

    def setup_options(args)
      options = parse_options(args)

      config = options[:config_file] ? parse_config(options[:config_file]) : {}

      Shoryuken.options.merge!(config).deep_symbolize_keys

      Shoryuken.options.merge!(options)
    end

    def parse_config(cfile)
      opts = {}
      if File.exist?(cfile)
        opts = YAML.load(ERB.new(IO.read(cfile)).result)
      end

      opts
    end

    def initialize_logger
      Shoryuken::Logging.initialize_logger(Shoryuken.options[:logfile]) if Shoryuken.options[:logfile]

      Shoryuken.logger.level = Logger::DEBUG if Shoryuken.options[:verbose]
    end

    def initialize_aws
      AWS.config Shoryuken.options[:aws] if Shoryuken.options[:aws]
    end

    def require_workers
      require Shoryuken.options[:require] if Shoryuken.options[:require]
    end
  end
end
