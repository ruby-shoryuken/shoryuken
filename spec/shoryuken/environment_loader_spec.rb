require 'spec_helper'
require 'active_job'

RSpec.describe Shoryuken::EnvironmentLoader do
  subject { described_class.new({}) }

  describe '#parse_queues' do
    before do
      allow(subject).to receive(:load_rails)
      allow(subject).to receive(:prefix_active_job_queue_names)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(subject).to receive(:validate_workers)
      allow(subject).to receive(:patch_deprecated_workers)
    end

    specify do
      Shoryuken.options[:queues] = ['queue1', ['queue2', 2]]
      subject.load

      expect(Shoryuken.groups['default'][:queues]).to eq(%w[queue1 queue2 queue2])
    end
  end

  describe '#prefix_active_job_queue_names' do
    before do
      allow(subject).to receive(:load_rails)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(subject).to receive(:validate_workers)
      allow(subject).to receive(:patch_deprecated_workers)

      ActiveJob::Base.queue_name_prefix    = 'test'
      ActiveJob::Base.queue_name_delimiter = '_'

      allow(Shoryuken).to receive(:active_job?).and_return(true)
    end

    specify do
      Shoryuken.active_job_queue_name_prefixing = true

      Shoryuken.options[:queues] = ['queue1', ['queue2', 2]]

      Shoryuken.options[:groups] = {
        'group1' => { queues: %w[group1_queue1 group1_queue2] }
      }

      subject.load

      expect(Shoryuken.groups['default'][:queues]).to eq(%w[test_queue1 test_queue2 test_queue2])
      expect(Shoryuken.groups['group1'][:queues]).to eq(%w[test_group1_queue1 test_group1_queue2])
    end
  end
end
