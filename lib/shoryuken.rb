require 'yaml'
require 'aws-sdk-v1'
require 'time'

require 'shoryuken/version'
require 'shoryuken/core_ext'
require 'shoryuken/util'
require 'shoryuken/client'
require 'shoryuken/worker'
require 'shoryuken/worker_loader'
require 'shoryuken/logging'
require 'shoryuken/middleware/chain'
require 'shoryuken/middleware/server/auto_delete'
require 'shoryuken/middleware/server/timing'

module Shoryuken
  DEFAULTS = {
    concurrency: 25,
    queues: [],
    aws: {},
    delay: 0,
    timeout: 8
  }

  @@workers       = {}
  @@queues        = []
  @@worker_loader = WorkerLoader

  class << self
    def options
      @options ||= DEFAULTS.dup
    end

    def register_worker(queue, clazz)
      if worker_class = @@workers[queue]
        if worker_class.get_shoryuken_options['batch'] == true || clazz.get_shoryuken_options['batch'] == true
          raise ArgumentError, "Could not register #{clazz} for '#{queue}', "\
            "because #{worker_class} is already registered for this queue, "\
            "and Shoryuken doesn't support a batchable worker for a queue with multiple workers"
        end
      end

      @@workers[queue] = clazz
    end

    def workers
      @@workers
    end

    def queues
      @@queues
    end

    def logger
      Shoryuken::Logging.logger
    end

    def worker_loader=(worker_loader)
      @@worker_loader = worker_loader
    end

    def worker_loader
      @@worker_loader
    end

    # Shoryuken.configure_server do |config|
    #   config.server_middleware do |chain|
    #     chain.add MyServerHook
    #   end
    # end
    def configure_server
      yield self
    end

    def server_middleware
      @server_chain ||= default_server_middleware
      yield @server_chain if block_given?
      @server_chain
    end


    private

    def default_server_middleware
      Middleware::Chain.new do |m|
        m.add Middleware::Server::Timing
        m.add Middleware::Server::AutoDelete
        if defined?(::ActiveRecord::Base)
          require 'shoryuken/middleware/server/active_record'
          m.add Middleware::Server::ActiveRecord
        end
        # TODO m.add Middleware::Server::RetryJobs
      end
    end
  end
end
