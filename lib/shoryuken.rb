require 'yaml'
require 'aws-sdk'
require 'time'

require 'shoryuken/version'
require 'shoryuken/core_ext'
require 'shoryuken/util'
require 'shoryuken/client'
require 'shoryuken/worker'
require 'shoryuken/logging'
require 'shoryuken/middleware/chain'
require 'shoryuken/middleware/server/auto_delete'
require 'shoryuken/middleware/server/logging'

module Shoryuken
  DEFAULTS = {
    concurrency: 25,
    queues: [],
    aws: {},
    delay: 25,
    timeout: 8
  }

  @@workers = {}
  @@queues = []

  def self.options
    @options ||= DEFAULTS.dup
  end

  def self.register_worker(queue, clazz)
    @@workers[queue] = clazz
  end

  def self.workers
    @@workers
  end

  def self.queues
    @@queues
  end

  def self.logger
    Shoryuken::Logging.logger
  end

  # Shoryuken.configure_server do |config|
  #   config.server_middleware do |chain|
  #     chain.add MyServerHook
  #   end
  # end
  def self.configure_server
    yield self
  end

  def self.server_middleware
    @server_chain ||= default_server_middleware
    yield @server_chain if block_given?
    @server_chain
  end


  private

  def self.default_server_middleware
    Middleware::Chain.new do |m|
      m.add Middleware::Server::Logging
      m.add Middleware::Server::AutoDelete
      # TODO m.add Middleware::Server::RetryJobs
    end
  end
end
