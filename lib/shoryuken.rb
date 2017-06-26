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
require 'shoryuken/options'

module Shoryuken
  extend SingleForwardable

  def_delegators(
    :'Shoryuken::Options',
    :queues,
    :ungrouped_queues,
    :add_queue,
    :add_group,
    :worker_registry,
    :worker_registry=,
    :polling_strategy,
    :start_callback,
    :start_callback=,
    :stop_callback,
    :stop_callback=,
    :active_job_queue_name_prefixing,
    :active_job_queue_name_prefixing=,
    :sqs_client,
    :sqs_client=,
    :sqs_client_receive_message_opts,
    :sqs_client_receive_message_opts=,
    :options,
    :logger,
    :register_worker,
    :configure_server,
    :server_middleware,
    :configure_client,
    :client_middleware,
    :default_worker_options,
    :default_worker_options=,
    :on_start,
    :on_stop,
    :on
  )
end

require 'shoryuken/extensions/active_job_adapter' if defined?(::ActiveJob)
