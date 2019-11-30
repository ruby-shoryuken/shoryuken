require 'spec_helper'
require 'shared_examples_for_active_job'
require 'shoryuken/extensions/active_job_adapter'
require 'shoryuken/extensions/active_job_concurrent_send_adapter'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter do
  include_examples 'active_job_adapters'

  let(:options) { {} }
  let(:error_handler) { -> {} }
  let(:success_handler) { -> {} }

  subject { described_class.new(success_handler, error_handler) }

  context 'when success' do
    it 'calls success_handler' do
      response = true
      allow(queue).to receive(:send_message).and_return(response)
      expect(success_handler).to receive(:call).with(response, job, options)

      subject.enqueue(job, options)
    end
  end

  context 'when failure' do
    it 'calls error_handler' do
      response = Aws::SQS::Errors::InternalError.new('error', 'error')

      allow(queue).to receive(:send_message).and_raise(response)
      expect(error_handler).to receive(:call).with(response, job, options).and_call_original

      subject.enqueue(job, options)
    end
  end
end
