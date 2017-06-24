require 'yaml'
require 'json'
require 'aws-sdk-core'
require 'time'
require 'concurrent'

require 'shoryuken/version'
require 'shoryuken/core_ext'
require 'shoryuken/util'
require 'shoryuken/logging'
require 'shoryuken/environment_loader'
require 'shoryuken/queue'
require 'shoryuken/message'
require 'shoryuken/client'
require 'shoryuken/worker'
require 'shoryuken/worker_registry'
require 'shoryuken/default_worker_registry'
require 'shoryuken/middleware/chain'
require 'shoryuken/middleware/server/auto_delete'
Shoryuken::Middleware::Server.autoload :AutoExtendVisibility, 'shoryuken/middleware/server/auto_extend_visibility'
require 'shoryuken/middleware/server/exponential_backoff_retry'
require 'shoryuken/middleware/server/timing'
require 'shoryuken/polling/base'
require 'shoryuken/polling/weighted_round_robin'
require 'shoryuken/polling/strict_priority'
require 'shoryuken/manager'
require 'shoryuken/launcher'
require 'shoryuken/processor'
require 'shoryuken/fetcher'

module Shoryuken
  DEFAULTS = {
    concurrency: 25,
    queues: [],
    aws: {},
    delay: 0,
    timeout: 8,
    lifecycle_events: {
      startup: [],
      dispatch: [],
      quiet: [],
      shutdown: []
    },
    polling_strategy: Polling::WeightedRoundRobin
  }.freeze

  @@queues                          = []
  @@worker_registry                 = DefaultWorkerRegistry.new
  @@active_job_queue_name_prefixing = false
  @@sqs_client                      = nil
  @@sqs_client_receive_message_opts = {}
  @@start_callback                  = nil
  @@stop_callback                   = nil

  class << self
    def queues
      @@queues
    end

    def add_queue(queue, priority = 1)
      priority.times { queues << queue }
    end

    def worker_registry
      @@worker_registry
    end

    def worker_registry=(worker_registry)
      @@worker_registry = worker_registry
    end

    def start_callback
      @@start_callback
    end

    def start_callback=(start_callback)
      @@start_callback = start_callback
    end

    def stop_callback
      @@stop_callback
    end

    def stop_callback=(stop_callback)
      @@stop_callback = stop_callback
    end

    def active_job_queue_name_prefixing
      @@active_job_queue_name_prefixing
    end

    def active_job_queue_name_prefixing=(active_job_queue_name_prefixing)
      @@active_job_queue_name_prefixing = active_job_queue_name_prefixing
    end

    def sqs_client
      @@sqs_client ||= Aws::SQS::Client.new
    end

    def sqs_client=(sqs_client)
      @@sqs_client = sqs_client
    end

    def sqs_client_receive_message_opts
      @@sqs_client_receive_message_opts
    end

    def sqs_client_receive_message_opts=(sqs_client_receive_message_opts)
      @@sqs_client_receive_message_opts = sqs_client_receive_message_opts
    end

    def options
      @@options ||= DEFAULTS.dup
    end

    def logger
      Shoryuken::Logging.logger
    end

    def register_worker(*args)
      @@worker_registry.register_worker(*args)
    end

    def configure_server
      yield self if server?
    end

    def server_middleware
      @@server_chain ||= default_server_middleware
      yield @@server_chain if block_given?
      @@server_chain
    end

    def configure_client
      yield self unless server?
    end

    def client_middleware
      @@client_chain ||= default_client_middleware
      yield @@client_chain if block_given?
      @@client_chain
    end

    def default_worker_options
      @@default_worker_options ||= {
        'queue'                   => 'default',
        'delete'                  => false,
        'auto_delete'             => false,
        'auto_visibility_timeout' => false,
        'retry_intervals'         => nil,
        'batch'                   => false
      }
    end

    def default_worker_options=(default_worker_options)
      @@default_worker_options = default_worker_options
    end

    def on_start(&block)
      @@start_callback = block
    end

    def on_stop(&block)
      @@stop_callback = block
    end

    # Register a block to run at a point in the Shoryuken lifecycle.
    # :startup, :quiet or :shutdown are valid events.
    #
    #   Shoryuken.configure_server do |config|
    #     config.on(:shutdown) do
    #       puts "Goodbye cruel world!"
    #     end
    #   end
    def on(event, &block)
      fail ArgumentError, "Symbols only please: #{event}" unless event.is_a?(Symbol)
      fail ArgumentError, "Invalid event name: #{event}" unless options[:lifecycle_events].key?(event)
      options[:lifecycle_events][event] << block
    end

    private

    def default_server_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Timing
        m.add Middleware::Server::ExponentialBackoffRetry
        m.add Middleware::Server::AutoDelete
        m.add Middleware::Server::AutoExtendVisibility
        if defined?(::ActiveRecord::Base)
          require 'shoryuken/middleware/server/active_record'
          m.add Middleware::Server::ActiveRecord
        end
      end
    end

    def default_client_middleware
      Middleware::Chain.new
    end

    def server?
      defined?(Shoryuken::CLI)
    end
  end
end

require 'shoryuken/extensions/active_job_adapter' if defined?(::ActiveJob)
