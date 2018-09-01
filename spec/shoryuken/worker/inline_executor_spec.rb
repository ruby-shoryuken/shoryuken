require 'spec_helper'

RSpec.describe Shoryuken::Worker::InlineExecutor do
  before do
    Shoryuken.worker_executor = described_class
  end

  describe '.perform_async' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform).with(anything, 'test')

      TestWorker.perform_async('test')
    end
  end

  describe '.perform_in' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform).with(anything, 'test')

      TestWorker.perform_in(60, 'test')
    end
  end

  context 'batch' do
    before do
      TestWorker.get_shoryuken_options['batch'] = true
    end

    after do
      TestWorker.get_shoryuken_options['batch'] = false
    end

    describe '.perform_async' do
      specify do
        expect_any_instance_of(TestWorker).to receive(:perform).with(anything, ['test'])

        TestWorker.perform_async('test')
      end
    end

    describe '.perform_in' do
      specify do
        expect_any_instance_of(TestWorker).to receive(:perform).with(anything, ['test'])

        TestWorker.perform_in(60, 'test')
      end
    end
  end
end
