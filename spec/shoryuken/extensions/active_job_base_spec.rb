require 'spec_helper'
require 'active_job'
require 'shoryuken/extensions/active_job_extensions'
require 'shoryuken/extensions/active_job_adapter'

RSpec.describe ActiveJob::Base do
  let(:queue_adapter) { ActiveJob::QueueAdapters::ShoryukenAdapter.new }

  subject do
    worker_class = Class.new(described_class)
    Object.const_set :MyWorker, worker_class
    worker_class.queue_adapter = queue_adapter
    worker_class
  end

  after do
    Object.send :remove_const, :MyWorker
  end

  describe '#perform_now' do
    it 'allows keyword args' do
      collaborator = double 'worker collaborator'
      subject.send(:define_method, :perform) do |**kwargs|
        collaborator.foo(**kwargs)
      end
      expect(collaborator).to receive(:foo).with(foo: 'bar')
      subject.perform_now foo: 'bar'
    end
  end

  describe '#perform_later' do
    it 'calls enqueue on the adapter with the expected job' do
      expect(queue_adapter).to receive(:enqueue) do |job|
        expect(job.arguments).to eq([1, 2])
      end

      subject.perform_later 1, 2
    end

    it 'passes message_group_id to the queue_adapter' do
      expect(queue_adapter).to receive(:enqueue) do |job|
        expect(job.sqs_send_message_parameters[:message_group_id]).to eq('group-2')
      end

      subject.set(message_group_id: 'group-2').perform_later 1, 2
    end

    it 'passes message_deduplication_id to the queue_adapter' do
      expect(queue_adapter).to receive(:enqueue) do |job|
        expect(job.sqs_send_message_parameters[:message_deduplication_id]).to eq('dedupe-id')
      end

      subject.set(message_deduplication_id: 'dedupe-id').perform_later 1, 2
    end

    it 'passes message_attributes to the queue_adapter' do
      message_attributes = {
        'custom_tracing_id' => {
          string_value: 'value',
          data_type: 'String'
        }
      }
      expect(queue_adapter).to receive(:enqueue) do |job|
        expect(job.sqs_send_message_parameters[:message_attributes]).to eq(message_attributes)
      end

      subject.set(message_attributes: message_attributes).perform_later 1, 2
    end

    it 'passes message_system_attributes to the queue_adapter' do
      message_system_attributes = {
        'AWSTraceHeader' => {
          string_value: 'trace_id',
          data_type: 'String'
        }
      }
      expect(queue_adapter).to receive(:enqueue) do |job|
        expect(job.sqs_send_message_parameters[:message_system_attributes]).to eq(message_system_attributes)
      end

      subject.set(message_system_attributes: message_system_attributes).perform_later 1, 2
    end
  end
end
