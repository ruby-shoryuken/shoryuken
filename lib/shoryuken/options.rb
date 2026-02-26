# frozen_string_literal: true

module Shoryuken
  # Stores and manages all Shoryuken configuration options.
  # This class is used internally to hold settings for workers, queues,
  # middleware, and other runtime configurations.
  class Options
    # Default configuration values for Shoryuken
    DEFAULTS = {
      thread_priority: -1,
      concurrency: 25,
      queues: [],
      aws: {},
      delay: 0.0,
      timeout: 8,
      lifecycle_events: {
        startup: [],
        dispatch: [],
        utilization_update: [],
        quiet: [],
        shutdown: [],
        stopped: []
      }
    }.freeze

    # @return [Boolean] whether to enable ActiveJob queue name prefixing
    # @return [Boolean] whether to cache SQS visibility timeout
    # @return [Hash{String => Hash}] the configured processing groups
    # @return [Object] the executor used to launch workers
    # @return [Proc] the code reloader proc for development environments
    # @return [Boolean] whether code reloading is enabled
    # @return [Proc, nil] callback to execute when server starts
    # @return [Proc, nil] callback to execute when server stops
    # @return [Class] the executor class for running workers
    # @return [Shoryuken::WorkerRegistry] the registry for worker classes
    # @return [Array<#call>] handlers for processing exceptions
    attr_accessor :active_job_queue_name_prefixing, :cache_visibility_timeout,
                  :groups, :launcher_executor, :reloader, :enable_reloading,
                  :start_callback, :stop_callback, :worker_executor, :worker_registry,
                  :exception_handlers

    # @return [Hash] the default options for workers
    # @return [Aws::SQS::Client] the SQS client instance
    # @return [Logger] the logger instance
    attr_writer :default_worker_options, :sqs_client, :logger

    # @return [Hash] options passed to SQS receive_message calls
    attr_reader :sqs_client_receive_message_opts

    # Initializes a new Options instance with default values
    def initialize
      self.groups = {}
      self.worker_registry = DefaultWorkerRegistry.new
      self.exception_handlers = [DefaultExceptionHandler]
      self.active_job_queue_name_prefixing = false
      self.worker_executor = Worker::DefaultExecutor
      self.cache_visibility_timeout = false
      self.reloader = proc { |&block| block.call }
      self.enable_reloading ||= false
      # this is needed for keeping backward compatibility
      @sqs_client_receive_message_opts ||= {}
    end

    # Checks if ActiveJob is available
    #
    # @return [Boolean] true if ActiveJob is defined
    def active_job?
      defined?(::ActiveJob)
    end

    # Adds a processing group with the specified concurrency and delay
    #
    # @param group [String] the name of the group
    # @param concurrency [Integer, nil] the number of concurrent workers for the group
    # @param delay [Float, nil] the delay between polling cycles
    # @param polling_strategy [Class, nil] the polling strategy class for the group
    # @return [Hash] the group configuration
    def add_group(group, concurrency = nil, delay: nil, polling_strategy: nil)
      concurrency ||= options[:concurrency]
      delay ||= options[:delay]

      groups[group] ||= {
        concurrency: concurrency,
        delay: delay,
        polling_strategy: polling_strategy,
        queues: []
      }
    end

    # Adds a queue to a processing group with the specified weight
    #
    # @param queue [String] the name of the queue
    # @param weight [Integer] the weight (priority) of the queue
    # @param group [String] the name of the group to add the queue to
    # @return [void]
    def add_queue(queue, weight, group)
      weight.times do
        groups[group][:queues] << queue
      end
    end

    # Returns all queues from all groups
    #
    # @return [Array<String>] flat array of all queue names
    def ungrouped_queues
      groups.values.flat_map { |options| options[:queues] }
    end

    # Returns the polling strategy class for a group
    #
    # @param group [String] the name of the group
    # @return [Class] the polling strategy class to use
    def polling_strategy(group)
      strategy = groups[group].to_h[:polling_strategy] ||
                 (group == 'default' ? options : options[:groups].to_h[group]).to_h[:polling_strategy]
      case strategy
      when 'WeightedRoundRobin', nil # Default case
        Polling::WeightedRoundRobin
      when 'StrictPriority'
        Polling::StrictPriority
      when String
        begin
          Object.const_get(strategy)
        rescue NameError
          raise Errors::InvalidPollingStrategyError, "#{strategy} is not a valid polling_strategy"
        end
      when Class
        strategy
      end
    end

    # Returns the polling delay for a group
    #
    # @param group [String] the name of the group
    # @return [Float] the delay in seconds
    def delay(group)
      groups[group].to_h.fetch(:delay, options[:delay]).to_f
    end

    # Returns the SQS client, initializing a default one if needed.
    # Uses AWS configuration from options[:aws] if available.
    #
    # @return [Aws::SQS::Client] the SQS client
    def sqs_client
      @sqs_client ||= Aws::SQS::Client.new(options[:aws])
    end

    # Sets the SQS client receive message options for the default group
    #
    # @param sqs_client_receive_message_opts [Hash] the options hash
    # @return [Hash] the options hash
    def sqs_client_receive_message_opts=(sqs_client_receive_message_opts)
      @sqs_client_receive_message_opts['default'] = sqs_client_receive_message_opts
    end

    # Returns the global options hash
    #
    # @return [Hash] the options hash
    def options
      @options ||= DEFAULTS.dup
    end

    # Returns the logger instance
    #
    # @return [Logger] the logger
    def logger
      @logger ||= Shoryuken::Logging.logger
    end

    # Returns the thread priority setting
    #
    # @return [Integer] the thread priority
    def thread_priority
      @thread_priority ||= options[:thread_priority]
    end

    # Sets the thread priority
    #
    # @param value [Integer] the thread priority value
    # @return [Integer] the thread priority
    attr_writer :thread_priority

    # Registers a worker class with the worker registry
    #
    # @param args [Array] arguments to pass to the registry
    # @return [void]
    def register_worker(*args)
      worker_registry.register_worker(*args)
    end

    # Yields self if running as a server for server-specific configuration
    #
    # @yield [Shoryuken::Options] the options instance
    # @return [void]
    def configure_server
      yield self if server?
    end

    # Returns the server middleware chain
    #
    # @yield [Shoryuken::Middleware::Chain] the middleware chain for configuration
    # @return [Shoryuken::Middleware::Chain] the server middleware chain
    def server_middleware
      @_server_chain ||= default_server_middleware
      yield @_server_chain if block_given?
      @_server_chain
    end

    # Yields self unless running as a server for client-specific configuration
    #
    # @yield [Shoryuken::Options] the options instance
    # @return [void]
    def configure_client
      yield self unless server?
    end

    # Returns the client middleware chain
    #
    # @yield [Shoryuken::Middleware::Chain] the middleware chain for configuration
    # @return [Shoryuken::Middleware::Chain] the client middleware chain
    def client_middleware
      @_client_chain ||= default_client_middleware
      yield @_client_chain if block_given?
      @_client_chain
    end

    # Returns the default worker options hash
    #
    # @return [Hash{String => Object}] the default worker options
    def default_worker_options
      @default_worker_options ||= {
        'queue' => 'default',
        'delete' => false,
        'auto_delete' => false,
        'auto_visibility_timeout' => false,
        'retry_intervals' => nil,
        'batch' => false
      }
    end

    # Registers a callback to run when the server starts
    #
    # @param block [Proc] the block to execute on start
    # @return [void]
    # @yield the block to execute on start
    def on_start(&block)
      self.start_callback = block
    end

    # Registers a callback to run when the server stops
    #
    # @param block [Proc] the block to execute on stop
    # @return [void]
    # @yield the block to execute on stop
    def on_stop(&block)
      self.stop_callback = block
    end

    # Registers a block to run at a point in the Shoryuken lifecycle.
    #
    # @param event [Symbol] the lifecycle event (:startup, :quiet, :shutdown, or :stopped)
    # @param block [Proc] the block to execute for the event
    # @return [void]
    # @raise [ArgumentError] if event is not a Symbol or not a valid event name
    # @yield the block to execute for the event
    # @example
    #   Shoryuken.configure_server do |config|
    #     config.on(:shutdown) do
    #       puts "Goodbye cruel world!"
    #     end
    #   end
    def on(event, &block)
      raise Errors::InvalidEventError, "Symbols only please: #{event}" unless event.is_a?(Symbol)
      raise Errors::InvalidEventError, "Invalid event name: #{event}" unless options[:lifecycle_events].key?(event)

      options[:lifecycle_events][event] << block
    end

    # Checks if running as a server (CLI mode)
    #
    # @return [Boolean] true if Shoryuken::CLI is defined
    def server?
      defined?(Shoryuken::CLI)
    end

    # Checks if visibility timeout caching is enabled
    #
    # @return [Boolean] true if caching is enabled
    def cache_visibility_timeout?
      @cache_visibility_timeout
    end

    # Checks if ActiveJob queue name prefixing is enabled
    #
    # @return [Boolean] true if prefixing is enabled
    def active_job_queue_name_prefixing?
      @active_job_queue_name_prefixing
    end

    private

    # Creates the default server middleware chain
    #
    # @return [Shoryuken::Middleware::Chain] the default middleware chain
    def default_server_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Timing
        m.add Middleware::Server::NonRetryableException
        m.add Middleware::Server::ExponentialBackoffRetry
        m.add Middleware::Server::AutoDelete
        m.add Middleware::Server::AutoExtendVisibility
        if defined?(::ActiveRecord::Base)
          require 'shoryuken/middleware/server/active_record'
          m.add Middleware::Server::ActiveRecord
        end
      end
    end

    # Creates the default client middleware chain
    #
    # @return [Shoryuken::Middleware::Chain] an empty middleware chain
    def default_client_middleware
      Middleware::Chain.new
    end
  end
end
