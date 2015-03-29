require 'yaml'
require 'aws-sdk-core'
require 'time'

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
require 'shoryuken/middleware/server/exponential_backoff_retry'
require 'shoryuken/middleware/server/timing'
require 'shoryuken/sns_arn'
require 'shoryuken/topic'

module Shoryuken
  DEFAULTS = {
    concurrency: 25,
    queues: [],
    aws: {},
    delay: 0,
    timeout: 8
  }

  @@queues          = []
  @@worker_registry = DefaultWorkerRegistry.new

  class << self
    def options
      @options ||= DEFAULTS.dup
    end

    def queues
      @@queues
    end

    def logger
      Shoryuken::Logging.logger
    end

    def register_worker(*args)
      worker_registry.register_worker(*args)
    end

    def worker_registry=(worker_registry)
      @@worker_registry = worker_registry
    end

    def worker_registry
      @@worker_registry
    end

    # Shoryuken.configure_server do |config|
    #   config.server_middleware do |chain|
    #     chain.add MyServerHook
    #   end
    # end
    def configure_server
      yield self if server?
    end

    def server_middleware
      @server_chain ||= default_server_middleware
      yield @server_chain if block_given?
      @server_chain
    end

    def default_worker_options
      @@default_worker_options ||= {
        'queue'                   => 'default',
        'delete'                  => false,
        'auto_delete'             => false,
        'auto_visibility_timeout' => false,
        'retry_intervals'         => nil,
        'batch'                   => false }
    end

    def default_worker_options=(options)
      @@default_worker_options = options
    end

    def on_aws_initialization(&block)
      @aws_initialization_callback = block
    end

    def on_start(&block)
      @start_callback = block
    end

    def on_stop(&block)
      @stop_callback = block
    end

    attr_reader :aws_initialization_callback,
                :start_callback,
                :stop_callback

    private

    def default_server_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Timing
        m.add Middleware::Server::ExponentialBackoffRetry
        m.add Middleware::Server::AutoDelete
        if defined?(::ActiveRecord::Base)
          require 'shoryuken/middleware/server/active_record'
          m.add Middleware::Server::ActiveRecord
        end
      end
    end

    def server?
      defined?(Shoryuken::CLI)
    end
  end
end

require 'shoryuken/extensions/active_job_adapter' if defined?(::ActiveJob)
