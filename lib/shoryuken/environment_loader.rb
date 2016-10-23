module Shoryuken
  class EnvironmentLoader
    attr_reader :options

    def self.load(options)
      new(options).load
    end

    def self.load_for_rails_console
      load(config_file: (Rails.root + 'config' + 'shoryuken.yml'))
    end

    def initialize(options)
      @options = options
    end

    def load
      load_rails if options[:rails]
      initialize_options
      initialize_logger
      merge_cli_defined_queues
      prefix_active_job_queue_names
      parse_queues
      require_workers
      initialize_aws
      validate_queues
      validate_workers
      patch_deprecated_workers
    end

    private

    def initialize_options
      Shoryuken.options.merge!(config_file_options)
      Shoryuken.options.merge!(options)
    end

    def config_file_options
      return {} unless (path = options[:config_file])

      fail ArgumentError, "The supplied config file '#{path}' does not exist" unless File.exist?(path)

      YAML.load(ERB.new(IO.read(path)).result).deep_symbolize_keys
    end

    def initialize_aws
      Shoryuken::AwsConfig.setup(Shoryuken.options[:aws])
    end

    def initialize_logger
      Shoryuken::Logging.initialize_logger(options[:logfile]) if options[:logfile]
      Shoryuken.logger.level = Logger::DEBUG if options[:verbose]
    end

    def load_rails
      # Adapted from: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/cli.rb

      require 'rails'
      if ::Rails::VERSION::MAJOR < 4
        require File.expand_path('config/environment.rb')
        ::Rails.application.eager_load!
      else
        # Painful contortions, see 1791 for discussion
        require File.expand_path('config/application.rb')
        ::Rails::Application.initializer 'shoryuken.eager_load' do
          ::Rails.application.config.eager_load = true
        end
        require 'shoryuken/extensions/active_job_adapter' if defined?(::ActiveJob)
        require File.expand_path('config/environment.rb')
      end
    end

    def merge_cli_defined_queues
      cli_defined_queues = options.delete(:queues) || []

      cli_defined_queues.each do |cli_defined_queue|
        Shoryuken.options[:queues].delete_if do |config_file_queue|
          config_file_queue[0] == cli_defined_queue[0]
        end

        Shoryuken.options[:queues] << cli_defined_queue
      end
    end

    def prefix_active_job_queue_names
      return unless defined? ::ActiveJob
      return unless Shoryuken.active_job_queue_name_prefixing

      queue_name_prefix = ::ActiveJob::Base.queue_name_prefix
      queue_name_delimiter = ::ActiveJob::Base.queue_name_delimiter

      # See https://github.com/rails/rails/blob/master/activejob/lib/active_job/queue_name.rb#L27
      Shoryuken.options[:queues].to_a.map! do |queue_name, weight|
        name_parts = [queue_name_prefix.presence, queue_name]
        prefixed_queue_name = name_parts.compact.join(queue_name_delimiter)
        [prefixed_queue_name, weight]
      end
    end

    def parse_queue(queue, weight = nil)
      [weight.to_i, 1].max.times { Shoryuken.queues << queue }
    end

    def parse_queues
      Shoryuken.options[:queues].to_a.each do |queue_and_weight|
        parse_queue(*queue_and_weight)
      end
    end

    def patch_deprecated_workers
      Shoryuken.worker_registry.queues.each do |queue|
        Shoryuken.worker_registry.workers(queue).each do |worker_class|
          if worker_class.instance_method(:perform).arity == 1
            Shoryuken.logger.warn { "[DEPRECATION] #{worker_class.name}#perform(sqs_msg) is deprecated. Please use #{worker_class.name}#perform(sqs_msg, body)" }

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

    def require_workers
      required = Shoryuken.options[:require]

      return unless required

      if File.directory?(required)
        Dir[File.join(required, '**', '*.rb')].each(&method(:require))
      else
        require required
      end
    end

    def validate_queues
      Shoryuken.logger.warn { 'No queues supplied' } if Shoryuken.queues.empty?

      non_existent_queues = []

      Shoryuken.queues.uniq.each do |queue|
        begin
          Shoryuken::Client.queues queue
        rescue Aws::SQS::Errors::NonExistentQueue
          non_existent_queues << queue
        end
      end

      fail ArgumentError, "The specified queue(s) #{non_existent_queues} do not exist" if non_existent_queues.any?
    end

    def validate_workers
      all_queues = Shoryuken.queues
      queues_with_workers = Shoryuken.worker_registry.queues

      unless defined?(::ActiveJob)
        (all_queues - queues_with_workers).each do |queue|
          Shoryuken.logger.warn { "No worker supplied for '#{queue}'" }
        end
      end
    end
  end
end
