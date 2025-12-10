# frozen_string_literal: true

module Shoryuken
  # Loads and configures the Shoryuken environment from configuration files
  # and command line options. Handles Rails integration and queue setup.
  class EnvironmentLoader
    # @return [Hash] the configuration options
    attr_reader :options

    # Sets up a new EnvironmentLoader with the given options
    #
    # @param options [Hash] configuration options
    # @option options [String] :config_file path to the configuration file
    # @option options [Boolean] :rails whether to initialize Rails
    # @option options [String] :logfile path to the log file
    # @option options [Boolean] :verbose whether to enable verbose logging
    # @option options [String] :require path to require workers from
    # @option options [Integer] :concurrency number of concurrent workers
    # @return [Shoryuken::EnvironmentLoader] the configured instance
    def self.setup_options(options)
      instance = new(options)
      instance.setup_options
      instance
    end

    # Loads the environment for Rails console usage
    #
    # @return [void]
    def self.load_for_rails_console
      instance = setup_options(config_file: (Rails.root + 'config' + 'shoryuken.yml'))
      instance.load
    end

    # Initializes a new EnvironmentLoader with the given options
    #
    # @param options [Hash] configuration options
    # @option options [String] :config_file path to the configuration file
    # @option options [Boolean] :rails whether to initialize Rails
    # @option options [String] :logfile path to the log file
    # @option options [Boolean] :verbose whether to enable verbose logging
    # @option options [String] :require path to require workers from
    # @option options [Integer] :concurrency number of concurrent workers
    def initialize(options)
      @options = options
    end

    # Sets up configuration options from file and initializes components
    #
    # @return [void]
    def setup_options
      initialize_rails if load_rails?
      initialize_options
      initialize_logger
    end

    # Loads the environment including queues and workers
    #
    # @return [void]
    def load
      prefix_active_job_queue_names
      parse_queues
      require_workers
      validate_queues
      validate_workers
    end

    private

    # Merges configuration file options with runtime options
    #
    # @return [void]
    def initialize_options
      Shoryuken.options.merge!(config_file_options)
      Shoryuken.options.merge!(options)
    end

    # Reads and parses the configuration file
    #
    # @return [Hash] the parsed configuration options
    def config_file_options
      return {} unless (path = options[:config_file])

      fail ArgumentError, "The supplied config file #{path} does not exist" unless File.exist?(path)

      if (result = YAML.load(ERB.new(IO.read(path)).result))
        Shoryuken::Helpers::HashUtils.deep_symbolize_keys(result)
      else
        {}
      end
    end

    # Initializes the logger with file output and verbosity settings
    #
    # @return [void]
    def initialize_logger
      Shoryuken::Logging.initialize_logger(Shoryuken.options[:logfile]) if Shoryuken.options[:logfile]
      Shoryuken.logger.level = Logger::DEBUG if Shoryuken.options[:verbose]
    end

    # Initializes the Rails environment
    #
    # @return [void]
    def initialize_rails
      # Adapted from: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/cli.rb

      require 'rails'
      if ::Rails::VERSION::MAJOR < 4
        require File.expand_path('config/environment.rb')
        ::Rails.application.eager_load!
      else
        # Painful contortions, see 1791 for discussion
        require File.expand_path('config/application.rb')
        if ::Rails::VERSION::MAJOR == 4
          ::Rails::Application.initializer 'shoryuken.eager_load' do
            ::Rails.application.config.eager_load = true
          end
        end
        ::Rails::Application.initializer 'shoryuken.set_reloader_hook' do |app|
          Shoryuken.reloader = proc do |&block|
            app.reloader.wrap do
              block.call
            end
          end
        end
        if Shoryuken.active_job?
          require 'active_job/extensions'
          require 'active_job/queue_adapters/shoryuken_adapter'
          require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'
        end
        require File.expand_path('config/environment.rb')
      end
    end

    # Checks if Rails should be loaded
    #
    # @return [Boolean] true if Rails should be initialized
    def load_rails?
      options[:rails]
    end

    # Prefixes a queue name with ActiveJob queue name prefix
    #
    # @param queue_name [String] the queue name to prefix
    # @param weight [Integer] the queue weight
    # @return [Array<String, Integer>] the prefixed queue name and weight
    def prefix_active_job_queue_name(queue_name, weight)
      return [queue_name, weight] if queue_name.start_with?('https://', 'arn:')

      queue_name_prefix = ::ActiveJob::Base.queue_name_prefix
      queue_name_delimiter = ::ActiveJob::Base.queue_name_delimiter

      # See https://github.com/rails/rails/blob/master/activejob/lib/active_job/queue_name.rb#L27
      name_parts = [queue_name_prefix.presence, queue_name]
      prefixed_queue_name = name_parts.compact.join(queue_name_delimiter)
      [prefixed_queue_name, weight]
    end

    # Prefixes all queue names with ActiveJob prefix if enabled
    #
    # @return [void]
    def prefix_active_job_queue_names
      return unless Shoryuken.active_job?
      return unless Shoryuken.active_job_queue_name_prefixing?

      Shoryuken.options[:queues].to_a.map! do |queue_name, weight|
        prefix_active_job_queue_name(queue_name, weight)
      end

      Shoryuken.options[:groups].to_a.map! do |group, options|
        if options[:queues]
          options[:queues].map! do |queue_name, weight|
            prefix_active_job_queue_name(queue_name, weight)
          end
        end

        [group, options]
      end
    end

    # Parses a single queue and adds it to a group
    #
    # @param queue [String] the queue name
    # @param weight [Integer] the queue weight
    # @param group [String] the group name
    # @return [void]
    def parse_queue(queue, weight, group)
      Shoryuken.add_queue(queue, [weight.to_i, 1].max, group)
    end

    # Parses all queues from configuration and adds them to groups
    #
    # @return [void]
    def parse_queues
      if Shoryuken.options[:queues].to_a.any?
        Shoryuken.add_group('default', Shoryuken.options[:concurrency])

        Shoryuken.options[:queues].to_a.each do |queue, weight|
          parse_queue(queue, weight, 'default')
        end
      end

      Shoryuken.options[:groups].to_a.each do |group, options|
        Shoryuken.add_group(group, options[:concurrency], delay: options[:delay])

        options[:queues].to_a.each do |queue, weight|
          parse_queue(queue, weight, group)
        end
      end
    end

    # Requires worker files from the configured path
    #
    # @return [void]
    def require_workers
      required = Shoryuken.options[:require]

      return unless required

      if File.directory?(required)
        Dir[File.join(required, '**', '*.rb')].each(&method(:require))
      else
        require required
      end
    end

    # Validates that all configured queues exist in SQS
    #
    # @return [void]
    # @raise [ArgumentError] if any queues do not exist
    def validate_queues
      return Shoryuken.logger.warn { 'No queues supplied' } if Shoryuken.ungrouped_queues.empty?

      non_existent_queues = []

      Shoryuken.ungrouped_queues.uniq.each do |queue|
        Shoryuken::Client.queues(queue)
      rescue Aws::Errors::NoSuchEndpointError, Aws::SQS::Errors::NonExistentQueue
        non_existent_queues << queue
      end

      return if non_existent_queues.none?

      # NOTE: HEREDOC's ~ operator removes indents, but is only available Ruby 2.3+
      # See github PR: https://github.com/ruby-shoryuken/shoryuken/pull/691#issuecomment-1007653595
      error_msg = <<-MSG.gsub(/^\s+/, '')
        The specified queue(s) #{non_existent_queues.join(', ')} do not exist.
        Try 'shoryuken sqs create QUEUE-NAME' for creating a queue with default settings.
        It's also possible that you don't have permission to access the specified queues.
      MSG

      fail(
        ArgumentError,
        error_msg
      )
    end

    # Validates that all queues have registered workers
    #
    # @return [void]
    def validate_workers
      return if Shoryuken.active_job?

      all_queues = Shoryuken.ungrouped_queues
      queues_with_workers = Shoryuken.worker_registry.queues

      (all_queues - queues_with_workers).each do |queue|
        Shoryuken.logger.warn { "No worker supplied for #{queue}" }
      end
    end
  end
end
