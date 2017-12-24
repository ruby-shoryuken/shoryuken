require 'spec_helper'

RSpec.describe Shoryuken::Worker::InlineExecutor do
  before do
    Shoryuken.worker_executor = described_class
  end

  describe '.perform_async' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform)

      TestWorker.perform_async('test')
    end
  end

  describe '.perform_in' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform)

      TestWorker.perform_in(60, 'test')
    end
  end
end
