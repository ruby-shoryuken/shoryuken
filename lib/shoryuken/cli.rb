$stdout.sync = true

require 'singleton'
require 'optparse'
require 'erb'

module Shoryuken
  class CLI
    include Util
    include Singleton

    attr_accessor :launcher

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
      write_pid

      @launcher = Shoryuken::Launcher.new

      begin
        launcher.run

        while readable_io = IO.select([self_read])
          signal = readable_io.first[0].gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        Shoryuken.logger.info 'Shutting down'
        launcher.stop
        exit(0)
      end
    end

    private

    def write_pid
      if path = Shoryuken.options[:pidfile]
        File.open(path, 'w') do |f|
          f.puts Process.pid
        end
      end
    end

    def parse_options(argv)
      opts = {}

      @parser = OptionParser.new do |o|
        o.on '-r', '--require [PATH|DIR]', 'Location of the worker' do |arg|
          opts[:require] = arg
        end

        o.on '-C', '--config PATH', 'path to YAML config file' do |arg|
          opts[:config_file] = arg
        end

        o.on '-L', '--logfile PATH', 'path to writable logfile' do |arg|
          opts[:logfile] = arg
        end

        o.on '-P', '--pidfile PATH', "path to pidfile" do |arg|
          opts[:pidfile] = arg
        end

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
        Shoryuken.logger.info @parser
        exit 1
      end
      @parser.parse!(argv)
      opts
    end

    def handle_signal(sig)
      Shoryuken.logger.info "Got #{sig} signal"

      case sig
      when 'USR1'
        Shoryuken.logger.info "Received USR1, no longer accepting new work"
        launcher.manager.async.stop
      when 'TTIN'
        Thread.list.each do |thread|
          Shoryuken.logger.info "Thread TID-#{thread.object_id.to_s(36)} #{thread['label']}"
          if thread.backtrace
            Shoryuken.logger.info thread.backtrace.join("\n")
          else
            Shoryuken.logger.info "<no backtrace available>"
          end
        end

        Shoryuken.logger.info "Ready processors: #{launcher.manager.instance_variable_get(:@ready).size}"
        Shoryuken.logger.info "Busy processors: #{launcher.manager.instance_variable_get(:@busy).size}"

        launcher.manager.instance_variable_get(:@queues).inject({}) do |weights, queue|
          weights[queue] = weights[queue].to_i + 1
          weights
        end.each do |queue, weight|
          Shoryuken.logger.info "Current queue '#{queue}' weight: #{weight}"
        end
      else
        raise Interrupt
      end
    end

    def setup_options(args)
      options = parse_options(args)

      config = options[:config_file] ? parse_config(options[:config_file]).deep_symbolize_keys : {}

      Shoryuken.options.merge!(config)

      Shoryuken.options.merge!(options)

      parse_queues
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

    def parse_queues
      Shoryuken.options[:queues].each { |queue_and_weight| parse_queue *queue_and_weight }
    end

    def parse_queue(queue, weight = nil)
      [weight.to_i, 1].max.times { Shoryuken.queues << queue }
    end
  end
end
