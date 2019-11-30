require 'spec_helper'
require 'shared_examples_for_active_job'
require 'shoryuken/extensions/active_job_adapter'
require 'shoryuken/extensions/active_job_concurrent_send_adapter'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter do
  include_examples 'active_job_adapters'

  let(:options) { {} }

  context '#success_hander' do
    it 'is called when a job succeeds' do
      response = true
      allow(queue).to receive(:send_message).and_return(response)
      expect(subject.success_handler).to receive(:call).with(response, job, options)

      subject.enqueue(job, options)
    end
  end

  context '#error_handler' do
    it 'is called when sending a job fails' do
      response = Aws::SQS::Errors::InternalError.new('error', 'error')
      allow(queue).to receive(:send_message).and_raise(response)
      expect(subject.error_handler).to receive(:call).with(response, job, options).and_call_original

      subject.enqueue(job, options)
    end
  end
end
