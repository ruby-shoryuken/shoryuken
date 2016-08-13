require 'spec_helper'
require 'shoryuken/manager'

RSpec::Matchers.define :queue_config_of do |expected|
  match do |actual|
    actual.name == expected
  end
end

RSpec.describe Shoryuken::Manager do
  let(:queue) { 'default' }
  let(:queues) { [queue] }
  let(:polling_strategy) { Shoryuken::Polling::WeightedRoundRobin.new(queues) }
  let(:fetcher) { Shoryuken::Fetcher.new }
  let(:condvar) do
    condvar = double(:condvar)
    allow(condvar).to receive(:signal).and_return(nil)
    condvar
  end
  let(:async_manager) { instance_double(described_class.name) }
  let(:concurrency) { 1 }

  subject { Shoryuken::Manager.new(condvar) }

  before(:each) do
    Shoryuken.options[:concurrency] = concurrency
    subject.fetcher = fetcher
    subject.polling_strategy = polling_strategy
    allow_any_instance_of(described_class).to receive(:async).and_return(async_manager)
  end

  after(:each) do
    Shoryuken.options[:concurrency] = 1
    TestWorker.get_shoryuken_options['batch'] = false
  end

  describe 'Invalid concurrency setting' do
    it 'raises ArgumentError if concurrency is not positive number' do
      Shoryuken.options[:concurrency] = -1
      expect { Shoryuken::Manager.new(nil) }
        .to raise_error(ArgumentError, 'Concurrency value -1 is invalid, it needs to be a positive number')
    end
  end

  describe '#dispatch' do
    it 'pauses when there are no active queues' do
      expect(polling_strategy).to receive(:next_queue).and_return(nil)
      expect_any_instance_of(described_class).to receive(:after)
      subject.dispatch
    end

    it 'calls dispatch_batch if worker wants batches' do
      TestWorker.get_shoryuken_options['batch'] = true
      expect_any_instance_of(described_class).to receive(:dispatch_batch).with(queue_config_of(queue))
      expect_any_instance_of(described_class).to receive(:async).and_return(async_manager)
      expect(async_manager).to receive(:dispatch)
      subject.dispatch
    end

    it 'calls dispatch_single_messages if worker wants single messages' do
      expect_any_instance_of(described_class).to receive(:dispatch_single_messages).
        with(queue_config_of(queue))
      expect(async_manager).to receive(:dispatch)
      subject.dispatch
    end
  end

  describe '#dispatch_batch' do
    it 'assings batch as a single message' do
      q = polling_strategy.next_queue
      messages = [1, 2, 3]
      expect(fetcher).to receive(:fetch).with(q, described_class::BATCH_LIMIT).and_return(messages)
      expect_any_instance_of(described_class).to receive(:assign).with(q.name, messages)
      subject.send(:dispatch_batch, q)
    end
  end

  describe '#dispatch_single_messages' do
    let(:concurrency) { 3 }

    it 'assings messages from batch one by one' do
      q = polling_strategy.next_queue
      messages = [1, 2, 3]
      expect(fetcher).to receive(:fetch).with(q, concurrency).and_return(messages)
      expect_any_instance_of(described_class).to receive(:assign).with(q.name, 1)
      expect_any_instance_of(described_class).to receive(:assign).with(q.name, 2)
      expect_any_instance_of(described_class).to receive(:assign).with(q.name, 3)
      subject.send(:dispatch_single_messages, q)
    end
  end
end
