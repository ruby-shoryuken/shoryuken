# frozen_string_literal: true

require 'aws-sdk-sqs'
require 'json'
require 'logger'
require 'time'
require 'concurrent'
require 'forwardable'
require 'zeitwerk'
require 'yaml'

# Set up Zeitwerk loader
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/active_job")
loader.setup

# Shoryuken is a super efficient AWS SQS thread based message processor.
# It provides a simple interface to process SQS messages using Ruby workers.
module Shoryuken
  extend SingleForwardable

  # Returns the global Shoryuken configuration options instance.
  # This is used internally for storing and accessing configuration settings.
  #
  # @return [Shoryuken::Options] The global options instance
  def self.shoryuken_options
    @_shoryuken_options ||= Shoryuken::Options.new
  end

  # Checks if the Shoryuken server is running and healthy.
  # A server is considered healthy when all configured processing groups
  # are running and able to process messages.
  #
  # @return [Boolean] true if the server is healthy
  def self.healthy?
    Shoryuken::Runner.instance.healthy?
  end

  def_delegators(
    :shoryuken_options,
    :active_job?,
    :add_group,
    :groups,
    :add_queue,
    :ungrouped_queues,
    :thread_priority,
    :thread_priority=,
    :worker_registry,
    :worker_registry=,
    :worker_executor,
    :worker_executor=,
    :launcher_executor,
    :launcher_executor=,
    :polling_strategy,
    :start_callback,
    :start_callback=,
    :stop_callback,
    :stop_callback=,
    :active_job_queue_name_prefixing?,
    :active_job_queue_name_prefixing=,
    :sqs_client,
    :sqs_client=,
    :sqs_client_receive_message_opts,
    :sqs_client_receive_message_opts=,
    :exception_handlers,
    :exception_handlers=,
    :options,
    :logger,
    :logger=,
    :register_worker,
    :configure_server,
    :server?,
    :server_middleware,
    :configure_client,
    :client_middleware,
    :default_worker_options,
    :default_worker_options=,
    :on_start,
    :on_stop,
    :on,
    :cache_visibility_timeout?,
    :cache_visibility_timeout=,
    :reloader,
    :reloader=,
    :enable_reloading,
    :enable_reloading=,
    :delay
  )
end

if Shoryuken.active_job?
  require 'active_job/extensions'
  require 'active_job/queue_adapters/shoryuken_adapter'
  require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'
end
