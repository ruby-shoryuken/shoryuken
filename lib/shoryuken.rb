require 'yaml'
require 'json'
require 'aws-sdk-core'
begin
  require 'aws-sdk-sqs' unless defined?(Aws::SQS)
rescue LoadError
  fail "AWS SDK 3 requires aws-sdk-sqs to be installed separately. Please add gem 'aws-sdk-sqs' to your Gemfile"
end
require 'time'
require 'concurrent'
require 'forwardable'

require 'shoryuken/version'
require 'shoryuken/core_ext'
require 'shoryuken/util'
require 'shoryuken/logging'
require 'shoryuken/environment_loader'
require 'shoryuken/queue'
require 'shoryuken/message'
require 'shoryuken/client'
require 'shoryuken/worker'
require 'shoryuken/worker/default_executor'
require 'shoryuken/worker/inline_executor'
require 'shoryuken/worker_registry'
require 'shoryuken/default_worker_registry'
require 'shoryuken/smart_batch_worker_registry'
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

  def_delegators(
    :'Shoryuken::Options',
    :active_job?,
    :add_group,
    :groups,
    :add_queue,
    :ungrouped_queues,
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
    :server?,
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

require 'shoryuken/extensions/active_job_adapter' if Shoryuken.active_job?
