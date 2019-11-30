require 'spec_helper'
require 'shoryuken/extensions/active_job_adapter'
require 'shared_examples_for_active_job'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenAdapter do
  include_examples 'active_job_adapters'
end
