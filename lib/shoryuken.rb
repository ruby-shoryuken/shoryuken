# frozen_string_literal: true

require 'yaml'
require 'json'
require 'aws-sdk-sqs'
require 'time'
require 'concurrent'
require 'forwardable'

require 'shoryuken/version'
require 'shoryuken/core_ext'
require 'shoryuken/util'
require 'shoryuken/logging'
require 'shoryuken/environment_loader'
require 'shoryuken/queue'
require 'shoryuken/inline_message'
require 'shoryuken/message'
require 'shoryuken/client'
require 'shoryuken/helpers/atomic_counter'
require 'shoryuken/helpers/atomic_boolean'
require 'shoryuken/helpers/atomic_hash'
require 'shoryuken/worker'
require 'shoryuken/worker/default_executor'
require 'shoryuken/worker/inline_executor'
require 'shoryuken/worker_registry'
require 'shoryuken/default_worker_registry'
require 'shoryuken/default_exception_handler'
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
require 'shoryuken/body_parser'
require 'shoryuken/fetcher'
require 'shoryuken/options'

module Shoryuken
  extend SingleForwardable

  def self.shoryuken_options
    @_shoryuken_options ||= Shoryuken::Options.new
  end

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
  require 'shoryuken/extensions/active_job_extensions'
  require 'shoryuken/extensions/active_job_adapter'
  require 'shoryuken/extensions/active_job_concurrent_send_adapter'
end
