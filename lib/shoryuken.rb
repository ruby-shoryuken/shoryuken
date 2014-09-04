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
require 'shoryuken/hello_worker'
require 'shoryuken/launcher'

module Shoryuken
  DEFAULTS = {
    concurrency: 25,
    queues: [],
    receive_message_options: {}
  }

  def self.options
    @options ||= DEFAULTS.dup
  end
end
