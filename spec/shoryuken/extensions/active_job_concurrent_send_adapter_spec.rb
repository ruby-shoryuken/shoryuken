require 'spec_helper'
require 'shared_examples_for_active_job'
require 'shoryuken/extensions/active_job_concurrent_send_adapter'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter do
  include_examples "active_job_adapters"
end
