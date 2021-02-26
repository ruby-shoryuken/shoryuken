require 'spec_helper'
require 'active_job'
require 'shoryuken/extensions/active_job_extensions'
require 'shoryuken/extensions/active_job_adapter'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenAdapter::JobWrapper do
  subject { described_class.new }

  describe '#perform' do
    it 'sets executions to reflect approximate receive count' do
      attributes = { 'ApproximateReceiveCount' => '42' }
      sqs_msg = double Shoryuken::Message, attributes: attributes
      job_hash = { 'arguments' => [1, 2, 3] }
      job_hash_with_executions = { 'arguments' => [1, 2, 3], 'executions' => 41 }
      expect(ActiveJob::Base).to receive(:execute).with(job_hash_with_executions)

      subject.perform sqs_msg, job_hash
    end
  end
end
