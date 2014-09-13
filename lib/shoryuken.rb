require 'yaml'
require 'aws-sdk'
require 'celluloid'
require 'time'

require 'shoryuken/version'
require 'shoryuken/core_ext'
require 'shoryuken/util'
require 'shoryuken/manager'
require 'shoryuken/processor'
require 'shoryuken/fetcher'
require 'shoryuken/client'
require 'shoryuken/worker'
require 'shoryuken/launcher'
require 'shoryuken/logging'

module Shoryuken
  DEFAULTS = {
    concurrency: 25,
    queues: [],
    receive_message_options: {},
    delay: 0
  }

  # { 'my_queue1' => Worker1
  #   'my_queue2' => Worker2 }
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
end
