# frozen_string_literal: true

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

  # Helper to create proper SQS message doubles
  def sqs_message(id: SecureRandom.uuid, body: 'test')
    double(Shoryuken::Message, message_id: id, body: body, receipt_handle: SecureRandom.uuid)
  end

  subject { Shoryuken::Manager.new('default', fetcher, polling_strategy, concurrency, executor) }

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
      message = sqs_message(id: 'msg-123')
      messages = [message]
      q = Shoryuken::Polling::QueueConfiguration.new(queue, {})

      expect(fetcher).to receive(:fetch).with(q, concurrency).and_return(messages)
      expect(subject).to receive(:fire_event).with(:dispatch, false, queue_name: q.name)
      expect(subject).to receive(:fire_event).with(:utilization_update,
                                                   false,
                                                   {
                                                     group: 'default',
                                                     busy_processors: 1,
                                                     max_processors: 1
                                                   })
      expect(Shoryuken::Processor).to receive(:process).with(q, message)
      expect(Shoryuken.logger).to receive(:info).never

      subject.send(:dispatch)
    end

    context 'and there are no messages in the queue' do
      specify do
        messages = %w[]
        q = Shoryuken::Polling::QueueConfiguration.new(queue, {})

        expect(fetcher).to receive(:fetch).with(q, concurrency).and_return(messages)
        expect(subject).to receive(:fire_event).with(:dispatch, false, queue_name: q.name)
        expect(polling_strategy).to receive(:messages_found).with(q.name, 0)
        expect(Shoryuken.logger).to receive(:info).never
        expect(Shoryuken::Processor).to receive(:process).never
        expect_any_instance_of(described_class).to receive(:assign).never

        subject.send(:dispatch)
      end
    end

    context 'when batch' do
      specify do
        messages = [sqs_message(id: 'msg-1'), sqs_message(id: 'msg-2'), sqs_message(id: 'msg-3')]
        q = Shoryuken::Polling::QueueConfiguration.new(queue, {})

        expect(fetcher).to receive(:fetch).with(q, described_class::BATCH_LIMIT).and_return(messages)
        expect(subject).to receive(:fire_event).with(:utilization_update,
                                                     false,
                                                     {
                                                       group: 'default',
                                                       busy_processors: 1,
                                                       max_processors: 1
                                                     })
        expect(subject).to receive(:fire_event).with(:dispatch, false, queue_name: q.name)
        allow(subject).to receive(:batched_queue?).with(q).and_return(true)
        expect(Shoryuken::Processor).to receive(:process).with(q, messages)
        expect(Shoryuken.logger).to receive(:info).never

        subject.send(:dispatch)
      end

      context 'and there are no messages in the queue' do
        specify do
          messages = %w[]
          q = Shoryuken::Polling::QueueConfiguration.new(queue, {})

          expect(fetcher).to receive(:fetch).with(q, described_class::BATCH_LIMIT).and_return(messages)
          expect(subject).to receive(:fire_event).with(:dispatch, false, queue_name: q.name)
          allow(subject).to receive(:batched_queue?).with(q).and_return(true)
          expect(polling_strategy).to receive(:messages_found).with(q.name, 0)
          expect(Shoryuken.logger).to receive(:info).never
          expect(Shoryuken::Processor).to receive(:process).never
          expect_any_instance_of(described_class).to receive(:assign).never

          subject.send(:dispatch)
        end
      end
    end
  end

  describe '#dispatch_single_messages' do
    let(:concurrency) { 3 }

    it 'assigns messages from batch one by one' do
      q = polling_strategy.next_queue
      msg1 = sqs_message(id: 'msg-1')
      msg2 = sqs_message(id: 'msg-2')
      msg3 = sqs_message(id: 'msg-3')
      messages = [msg1, msg2, msg3]
      expect(fetcher).to receive(:fetch).with(q, concurrency).and_return(messages)
      expect_any_instance_of(described_class).to receive(:assign).with(q.name, msg1)
      expect_any_instance_of(described_class).to receive(:assign).with(q.name, msg2)
      expect_any_instance_of(described_class).to receive(:assign).with(q.name, msg3)
      subject.send(:dispatch_single_messages, q)
    end
  end

  describe '#processor_done' do
    let(:sqs_queue)         { double Shoryuken::Queue }

    before do
      allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
    end

    context 'when queue.fifo? is true' do
      it 'calls message_processed on strategy' do
        expect(sqs_queue).to receive(:fifo?).and_return(true)
        expect(polling_strategy).to receive(:message_processed).with(queue)
        subject.send(:processor_done, queue)
      end
    end

    context 'when queue.fifo? is false' do
      it 'does not call message_processed on strategy' do
        expect(sqs_queue).to receive(:fifo?).and_return(false)
        expect(polling_strategy).to_not receive(:message_processed)
        subject.send(:processor_done, queue)
      end
    end
  end

  describe '#running?' do
    context 'when the executor is running' do
      before do
        allow(executor).to receive(:running?).and_return(true)
      end

      it 'returns true' do
        expect(subject.running?).to be true
      end
    end

    context 'when the executor is not running' do
      before do
        allow(executor).to receive(:running?).and_return(false)
      end

      it 'returns false' do
        expect(subject.running?).to be false
      end
    end
  end
end
