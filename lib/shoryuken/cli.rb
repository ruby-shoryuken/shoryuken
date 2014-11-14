$stdout.sync = true

require 'singleton'
require 'optparse'
require 'erb'

require 'shoryuken'

module Shoryuken
  class CLI
    include Util
    include Singleton

    attr_accessor :launcher

    def run(args)
      self_read, self_write = IO.pipe

      %w[INT TERM USR1 USR2 TTIN].each do |sig|
        trap sig do
          self_write.puts(sig)
        end
      end

      setup_options(args) do |cli_options|
        # this needs to happen before configuration is parsed, since it may depend on Rails env
        load_rails if cli_options[:rails]
      end
      initialize_logger
      require_workers
      validate!
      patch_deprecated_workers!
      daemonize
      write_pid
      load_celluloid

      require 'shoryuken/launcher'
      @launcher = Shoryuken::Launcher.new

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

    def load_rails
      # Adapted from: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/cli.rb

      require 'rails'
      if ::Rails::VERSION::MAJOR < 4
        require File.expand_path("config/environment.rb")
        ::Rails.application.eager_load!
      else
        # Painful contortions, see 1791 for discussion
        require File.expand_path("config/application.rb")
        ::Rails::Application.initializer "shoryuken.eager_load" do
          ::Rails.application.config.eager_load = true
        end
        require File.expand_path("config/environment.rb")
      end

      logger.info "Rails environment loaded"
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

      initialize_logger
    end

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
        o.on '-c', '--concurrency INT', 'Processor threads to use' do |arg|
          opts[:concurrency] = Integer(arg)
        end

        o.on '-d', '--daemon', 'Daemonize process' do |arg|
          opts[:daemon] = arg
        end

        o.on '-q', '--queue QUEUE[,WEIGHT]...', 'Queues to process with optional weights' do |arg|
          queue, weight = arg.split(',')
          parse_queue queue, weight
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

    def setup_options(args)
      options = parse_options(args)

      # yield parsed options in case we need to do more setup before configuration is parsed
      yield(options) if block_given?

      config = options[:config_file] ? parse_config(options[:config_file]).deep_symbolize_keys : {}

      Shoryuken.options.merge!(config)

      Shoryuken.options.merge!(options)

      parse_queues
    end

    def parse_config(config_file)
      if File.exist?(config_file)
        YAML.load(ERB.new(IO.read(config_file)).result)
      else
        raise ArgumentError, "Config file #{config_file} does not exist"
      end
    end

    def initialize_logger
      Shoryuken::Logging.initialize_logger(Shoryuken.options[:logfile]) if Shoryuken.options[:logfile]

      Shoryuken.logger.level = Logger::DEBUG if Shoryuken.options[:verbose]
    end

    def validate!
      raise ArgumentError, 'No queues supplied' if Shoryuken.queues.empty?

      Shoryuken.queues.each do |queue|
        logger.warn "No worker supplied for '#{queue}'" unless Shoryuken.workers.include? queue
      end

      if Shoryuken.options[:aws][:access_key_id].nil? && Shoryuken.options[:aws][:secret_access_key].nil?
        if ENV['AWS_ACCESS_KEY_ID'].nil? && ENV['AWS_SECRET_ACCESS_KEY'].nil?
          raise ArgumentError, 'No AWS credentials supplied'
        end
      end

      initialize_aws

      Shoryuken.queues.uniq.each do |queue|
        # validate all queues and AWS credentials consequently
        begin
          Shoryuken::Client.queues queue
        rescue AWS::SQS::Errors::NonExistentQueue => e
          raise ArgumentError, "Queue '#{queue}' does not exist"
        rescue => e
          raise
        end
      end
    end

    def initialize_aws
      # aws-sdk tries to load the credentials from the ENV variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
      # when not explicit supplied
      AWS.config Shoryuken.options[:aws] if Shoryuken.options[:aws]
    end

    def require_workers
      require Shoryuken.options[:require] if Shoryuken.options[:require]
    end

    def parse_queues
      Shoryuken.options[:queues].to_a.each { |queue_and_weight| parse_queue *queue_and_weight }
    end

    def parse_queue(queue, weight = nil)
      [weight.to_i, 1].max.times { Shoryuken.queues << queue }
    end

    def patch_deprecated_workers!
      Shoryuken.workers.each do |queue, worker_class|
        if worker_class.instance_method(:perform).arity == 1
          logger.warn "[DEPRECATION] #{worker_class.name}#perform(sqs_msg) is deprecated. Please use #{worker_class.name}#perform(sqs_msg, body)"

          worker_class.class_eval do
            alias_method :deprecated_perform, :perform

            def perform(sqs_msg, body = nil)
              deprecated_perform(sqs_msg)
            end
          end
        end
      end
    end
  end
end
