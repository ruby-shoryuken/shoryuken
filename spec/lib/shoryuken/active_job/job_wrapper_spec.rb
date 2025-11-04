# frozen_string_literal: true

require 'active_job'
require 'active_job/extensions'
require 'active_job/queue_adapters/shoryuken_adapter'

RSpec.describe Shoryuken::ActiveJob::JobWrapper do
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