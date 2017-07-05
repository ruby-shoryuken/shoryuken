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
  let(:fetcher) { double Shoryuken::Fetcher }
  let(:concurrency) { 1 }

  subject { Shoryuken::Manager.new(fetcher, polling_strategy, concurrency) }

  before do
    allow(fetcher).to receive(:fetch).and_return([])
  end

  after do
    Shoryuken.options[:concurrency] = 1
    TestWorker.get_shoryuken_options['batch'] = false
  end

  describe '#start' do
    xit 'pauses when there are no active queues' do
      expect(polling_strategy).to receive(:next_queue).and_return(nil)
      expect_any_instance_of(described_class).to receive(:after)
      subject.start
    end

    xit 'calls dispatch_batch if worker wants batches' do
      TestWorker.get_shoryuken_options['batch'] = true
      expect_any_instance_of(described_class).to receive(:dispatch_batch).with(queue_config_of(queue))
      expect(subject).to receive(:dispatch_later)
      subject.start
    end

    xit 'calls dispatch_single_messages if worker wants single messages' do
      expect_any_instance_of(described_class).to receive(:dispatch_single_messages).
        with(queue_config_of(queue))
      expect(subject).to receive(:dispatch_later)
      subject.start
    end
  end

  describe '#dispatch' do
    it 'fires a dispatch event' do
      # prevent dispatch loop
      allow(subject).to receive(:stopped?).and_return(false, true)

      expect(subject).to receive(:fire_event).with(:dispatch)
      expect(Shoryuken.logger).to_not receive(:info)

      subject.send(:dispatch)
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
