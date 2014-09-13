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

module Shoryuken
  DEFAULTS = {
    concurrency: 25,
    queues: [],
    receive_message_options: {}
  }

  # { 'my_queue1' => Worker1
  #   'my_queue2' => Worker2 }
  @@workers = {}

  def self.options
    @options ||= DEFAULTS.dup
  end

  def self.register_worker(queue, clazz)
    @@workers[queue] ||= clazz
  end

  def self.workers
    @@workers
  end

  def self.logger
    Shoryuken::Util.logger
  end
end

require 'shoryuken/echo_worker'
