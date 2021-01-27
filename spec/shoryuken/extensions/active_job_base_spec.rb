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

  describe '#perform_later' do
    it 'calls enqueue on the adapter with the expected job' do
      expect(queue_adapter).to receive(:enqueue) do |job|
        expect(job.arguments).to eq([1, 2])
      end

      subject.perform_later 1, 2
    end
  end
end
