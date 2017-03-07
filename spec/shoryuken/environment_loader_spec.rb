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

    it 'parses' do
      Shoryuken.options[:queues] = ['queue_1']
      subject.load

      expect(Shoryuken.queues).to eq(%w(queue_1))
    end

    context 'with priority' do
      it 'parses' do
        Shoryuken.options[:queues] = ['queue_1', ['queue_2', 2]]
        subject.load

        expect(Shoryuken.queues).to eq(%w(queue_1 queue_2 queue_2))
      end
    end
  end
end
