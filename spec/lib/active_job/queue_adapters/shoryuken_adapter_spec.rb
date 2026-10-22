# frozen_string_literal: true

require 'shared_examples_for_active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_support/core_ext/numeric/time'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenAdapter do
  include_examples 'active_job_adapters'

  describe '#enqueue_after_transaction_commit?' do
    it 'returns true to support Rails 7.2+ transaction commit behavior' do
      adapter = described_class.new
      expect(adapter.enqueue_after_transaction_commit?).to eq(true)
    end
  end

  describe '.instance' do
    it 'returns the same instance (singleton pattern)' do
      instance1 = described_class.instance
      instance2 = described_class.instance
      expect(instance1).to be(instance2)
    end

    it 'returns a ShoryukenAdapter instance' do
      expect(described_class.instance).to be_a(described_class)
    end
  end

end