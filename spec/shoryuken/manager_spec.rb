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
  let(:executor) { Concurrent::ImmediateExecutor.new }

  subject { Shoryuken::Manager.new(fetcher, polling_strategy, concurrency, executor) }

  before do
    allow(fetcher).to receive(:fetch).and_return([])
  end

  after do
    Shoryuken.options[:concurrency] = 1
    TestWorker.get_shoryuken_options['batch'] = false
  end

  describe '#stop' do
    specify do
      allow(subject).to receive(:running?).and_return(true, true, false)
      expect(subject).to receive(:dispatch).once.and_call_original
      expect(subject).to receive(:dispatch_loop).twice.and_call_original
      subject.start
    end
  end

  describe '#start' do
    before do
      # prevent dispatch loop
      allow(subject).to receive(:running?).and_return(true, true, false)
    end

    it 'pauses when there are no active queues' do
      expect(polling_strategy).to receive(:next_queue).and_return(nil)
      expect(subject).to receive(:dispatch).and_call_original
      subject.start
    end

    it 'calls dispatch_batch if worker wants batches' do
      TestWorker.get_shoryuken_options['batch'] = true
      expect(subject).to receive(:dispatch_batch).with(queue_config_of(queue))
      subject.start
    end

    it 'calls dispatch_single_messages if worker wants single messages' do
      expect(subject).to receive(:dispatch_single_messages).with(queue_config_of(queue))
      subject.start
    end
  end

  describe '#dispatch' do
    before do
      allow(subject).to receive(:running?).and_return(true, true, false)
    end

    specify do
      message  = ['test1']
      messages = [message]
      q = Shoryuken::Polling::QueueConfiguration.new(queue, {})

      expect(fetcher).to receive(:fetch).with(q, concurrency).and_return(messages)
      expect(subject).to receive(:fire_event).with(:dispatch, false, queue_name: q.name)
      expect(Shoryuken::Processor).to receive(:process).with(q, message)
      expect(Shoryuken.logger).to_not receive(:info)

      subject.send(:dispatch)
    end

    context 'when batch' do
      specify do
        messages = %w[test1 test2 test3]
        q = Shoryuken::Polling::QueueConfiguration.new(queue, {})

        expect(fetcher).to receive(:fetch).with(q, described_class::BATCH_LIMIT).and_return(messages)
        expect(subject).to receive(:fire_event).with(:dispatch, false, queue_name: q.name)
        allow(subject).to receive(:batched_queue?).with(q).and_return(true)
        expect(Shoryuken::Processor).to receive(:process).with(q, messages)
        expect(Shoryuken.logger).to_not receive(:info)

        subject.send(:dispatch)
      end
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
