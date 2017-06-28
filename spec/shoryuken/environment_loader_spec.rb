require 'spec_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Shoryuken::EnvironmentLoader do
  subject { described_class.new({}) }

  describe '#parse_queues' do
    before do
      # TODO proper test other methods
      allow(subject).to receive(:load_rails).with(anything)
      allow(subject).to receive(:prefix_active_job_queue_names)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(subject).to receive(:validate_workers)
      allow(subject).to receive(:patch_deprecated_workers)
    end

    specify do
      Shoryuken.options[:queues] = ['queue1', ['queue2', 2]]
      subject.load

      expect(Shoryuken.groups['default'][:queues]).to eq(%w(queue1 queue2 queue2))
    end
  end
end
