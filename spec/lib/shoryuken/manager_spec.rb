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
  let(:client) { double(Aws::SQS::Client, change_message_visibility_batch: double(failed: [])) }

  subject { Shoryuken::Manager.new('default', fetcher, polling_strategy, concurrency, executor) }

  before do
    allow(fetcher).to receive(:fetch).and_return([])
  end

  after do
    Shoryuken.options[:concurrency] = 1
    TestWorker.get_shoryuken_options['batch'] = false
  end

  def build_message(receipt_handle, queue_url = 'queue-url')
    double(
      Shoryuken::Message,
      message_id: SecureRandom.uuid,
      queue_url: queue_url,
      client: client,
      data: double(receipt_handle: receipt_handle)
    )
  end

  describe '#stop' do
    specify do
      allow(subject).to receive(:running?).and_return(true, true, false)
      expect(subject).to receive(:dispatch).once.and_call_original
      expect(subject).to receive(:dispatch_loop).twice.and_call_original
      subject.start
    end
  end

  describe '#await_dispatching_in_progress' do
    it 'returns for repeated graceful stops (e.g. TSTP followed by USR1)' do
      subject.stop_new_dispatching
      # The dispatch loop observes the stop flag and releases all waiters
      subject.start

      waiter = Thread.new do
        subject.await_dispatching_in_progress
        subject.await_dispatching_in_progress
      end

      expect(waiter.join(5)).to eq(waiter), 'await_dispatching_in_progress deadlocked on a repeated stop'
    end

    it 'returns when stopped before the dispatch loop ever runs' do
      # No #start here: the dispatch loop never runs, so there is nothing to
      # observe the stop flag and close the signal - stop_new_dispatching must
      # release waiters itself.
      subject.stop_new_dispatching

      waiter = Thread.new { subject.await_dispatching_in_progress }

      expect(waiter.join(5)).to eq(waiter), 'await_dispatching_in_progress deadlocked when start never ran'
    end

    context 'when the executor rejects the dispatch post' do
      let(:executor) do
        double('executor', running?: true).tap do |rejecting_executor|
          allow(rejecting_executor).to receive(:post).and_raise(Concurrent::RejectedExecutionError)
        end
      end

      it 'releases waiters instead of leaving the signal queue unsignaled' do
        # A hard stop can shut the executor down between the running? check and
        # the post; the dispatch chain must still release stop waiters
        subject.start

        waiter = Thread.new { subject.await_dispatching_in_progress }

        expect(waiter.join(5)).to eq(waiter), 'await_dispatching_in_progress deadlocked after a rejected post'
      end
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
      expect(subject).to receive(:fire_event).with(
        :utilization_update,
        false,
        {
          group: 'default',
          busy_processors: 1,
          max_processors: 1
        }
      )
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
        messages = %w[test1 test2 test3]
        q = Shoryuken::Polling::QueueConfiguration.new(queue, {})

        expect(fetcher).to receive(:fetch).with(q, described_class::BATCH_LIMIT).and_return(messages)
        expect(subject).to receive(:fire_event).with(
          :utilization_update,
          false,
          {
            group: 'default',
            busy_processors: 1,
            max_processors: 1
          }
        )
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

  context 'with an executor that is not a concurrent-ruby one' do
    let(:executor) do
      Class.new do
        attr_reader :posted

        def initialize
          @posted = []
        end

        def post(&block)
          @posted << block
          true
        end

        def running?
          true
        end
      end.new
    end
    let(:sqs_msg) { double(Shoryuken::Message, message_id: SecureRandom.uuid) }

    before do
      allow(fetcher).to receive(:fetch).and_return([sqs_msg])
      allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(double(Shoryuken::Queue, fifo?: false))
      allow(Shoryuken::Processor).to receive(:process)

      subject.start
      # Runs the posted dispatch, which posts the processing of the fetched message first
      executor.posted.shift.call
    end

    it 'processes the fetched message on it' do
      executor.posted.shift.call

      expect(Shoryuken::Processor).to have_received(:process).with(queue, sqs_msg)
    end

    it 'does not raise a processing error into it' do
      allow(Shoryuken::Processor).to receive(:process).and_raise('processing failed')

      expect { executor.posted.shift.call }.not_to raise_error
    end
  end

  context 'when every processor is busy' do
    let(:executor) do
      Class.new do
        attr_reader :posted

        def initialize
          @posted = ::Queue.new
        end

        def post(&block)
          @posted << block
          true
        end

        def running?
          true
        end
      end.new
    end
    let(:fetcher) { Shoryuken::Fetcher.new('default') }
    let(:fifo) { false }
    let(:messages) { Array.new(concurrency) { double(Shoryuken::Message, message_id: SecureRandom.uuid) } }

    before do
      stub_const("#{described_class}::MIN_DISPATCH_INTERVAL", 30)
      allow(fetcher).to receive(:fetch).and_return(messages, [])
      allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(double(Shoryuken::Queue, fifo?: fifo, name: queue))
      allow(Shoryuken::Processor).to receive(:process)
    end

    def occupy_processors(dispatches = 1)
      processings = []
      subject.start
      next_dispatch = executor.posted.pop

      dispatches.times do
        next_dispatch.call
        posted = Array.new(executor.posted.size) { executor.posted.pop }
        next_dispatch = posted.pop
        processings.concat(posted)
      end

      [processings, next_dispatch]
    end

    def expect_dispatch_once_free(free)
      processings, next_dispatch = occupy_processors(yield)
      dispatcher = Thread.new { next_dispatch.call }
      Thread.pass until dispatcher.status == 'sleep' || !dispatcher.alive?

      processings.first(free - 1).each(&:call)
      expect(dispatcher.join(0.3)).to be_nil, "the dispatch did not wait for #{free} free processors" if free > 1

      processings[free - 1].call
      expect(dispatcher.join(5)).to eq(dispatcher), 'the dispatch waited for MIN_DISPATCH_INTERVAL'
    end

    it 'dispatches again as soon as a processor finishes' do
      expect_dispatch_once_free(1) { 1 }
    end

    it 'waits up to MIN_DISPATCH_INTERVAL when no processor finishes' do
      stub_const("#{described_class}::MIN_DISPATCH_INTERVAL", 0.2)
      _, next_dispatch = occupy_processors
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      next_dispatch.call

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 0.2
      expect(fetcher).to have_received(:fetch).once
    end

    context 'with more than one processor' do
      let(:concurrency) { 2 }

      it 'waits until enough processors are free to fill one receive' do
        expect_dispatch_once_free(2) { 1 }
      end

      it 'waits at most MIN_DISPATCH_INTERVAL in total' do
        stub_const("#{described_class}::MIN_DISPATCH_INTERVAL", 1)
        processings, next_dispatch = occupy_processors
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        dispatcher = Thread.new { next_dispatch.call }

        sleep(0.5)
        processings.first.call

        expect(dispatcher.join(5)).to eq(dispatcher)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be_between(1, 1.3)
        expect(fetcher).to have_received(:fetch).twice
      end

      it 'dispatches when the queue lookup fails' do
        allow(fetcher).to receive(:receive_limit).and_raise(Seahorse::Client::NetworkingError.new(StandardError.new))

        expect_dispatch_once_free(1) { 1 }
        expect(subject).not_to be_failed
      end
    end

    context 'with more processors than one receive can return' do
      let(:concurrency) { 11 }

      it 'waits until FETCH_LIMIT processors are free' do
        expect_dispatch_once_free(Shoryuken::Fetcher::FETCH_LIMIT) { 1 }
      end
    end

    context 'with a FIFO queue' do
      let(:concurrency) { 2 }
      let(:fifo) { true }

      it 'dispatches again as soon as a processor finishes' do
        allow(fetcher).to receive(:fetch).and_return([messages.first], [messages.last], [])

        expect_dispatch_once_free(1) { 2 }
      end
    end

    context 'with a max_number_of_messages receive option' do
      let(:concurrency) { 2 }

      it 'waits only for that many free processors' do
        Shoryuken.sqs_client_receive_message_opts[queue] = { max_number_of_messages: 1 }

        expect_dispatch_once_free(1) { 1 }
      end
    end

    context 'with a batched queue' do
      let(:concurrency) { 2 }

      it 'dispatches again as soon as a processor finishes' do
        TestWorker.get_shoryuken_options['batch'] = true
        allow(fetcher).to receive(:fetch).and_return([messages.first], [messages.last], [])

        expect_dispatch_once_free(1) { 2 }
      end
    end

    context 'with no processors' do
      let(:concurrency) { 0 }

      it 'waits MIN_DISPATCH_INTERVAL instead of spinning' do
        stub_const("#{described_class}::MIN_DISPATCH_INTERVAL", 0.2)
        subject.start
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        executor.posted.pop.call

        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 0.2
        expect(fetcher).not_to have_received(:fetch)
      end
    end
  end

  describe '#assign' do
    let(:sqs_msg) { build_message('m1') }
    let(:other_msg) { build_message('m2') }
    let(:sqs_queue) { double(Shoryuken::Queue, fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
      allow(Shoryuken::Processor).to receive(:process)
    end

    def released_entries(queue_url = 'queue-url')
      entries = []
      expect(client).to have_received(:change_message_visibility_batch).with(hash_including(queue_url: queue_url)) do |args|
        entries.concat(args[:entries])
      end
      entries
    end

    it 'runs completion exactly once on success' do
      expect(subject).to receive(:processor_done).with(queue, sqs_msg, true).once.and_call_original

      subject.send(:assign, queue, sqs_msg)

      expect(subject.send(:busy)).to eq(0)
    end

    it 'runs completion exactly once when processing raises' do
      allow(Shoryuken::Processor).to receive(:process).and_raise('processing failed')

      expect(subject).to receive(:processor_done).with(queue, sqs_msg, true).once.and_call_original

      subject.send(:assign, queue, sqs_msg)

      expect(subject.send(:busy)).to eq(0)
    end

    it 'does not release a message it processes' do
      subject.send(:assign, queue, sqs_msg)

      expect(client).not_to have_received(:change_message_visibility_batch)
    end

    context 'when the manager is not running' do
      before { allow(subject).to receive(:running?).and_return(false) }

      it 'releases the message by setting its visibility timeout to 0' do
        expect(subject.send(:assign, queue, sqs_msg)).to be_nil

        expect(released_entries).to eq([{ id: '0', receipt_handle: 'm1', visibility_timeout: 0 }])
        expect(Shoryuken::Processor).not_to have_received(:process)
      end

      it 'releases every message of a batch with one request' do
        subject.send(:assign, queue, [sqs_msg, other_msg])

        expect(client).to have_received(:change_message_visibility_batch).once
        expect(released_entries.map { |entry| entry[:receipt_handle] }).to eq(%w[m1 m2])
      end
    end

    it 'removes the message from the in-flight list once when completion raises' do
      allow(sqs_queue).to receive(:fifo?).and_return(true)
      allow(polling_strategy).to receive(:message_processed).and_raise('callback failed')

      subject.send(:assign, queue, sqs_msg)

      expect(polling_strategy).to have_received(:message_processed).once
      expect(subject.send(:busy)).to eq(0)
    end

    context 'when the executor rejects the worker post' do
      # running? true so #assign proceeds past its guard and post rejecting -
      # exactly the shutdown race / saturated bounded launcher_executor case
      let(:executor) do
        double('executor', running?: true).tap do |rejecting_executor|
          allow(rejecting_executor).to receive(:post).and_raise(Concurrent::RejectedExecutionError)
        end
      end

      it 'removes the message from the in-flight list and does not leak it' do
        # The posted block never runs, so completion must not run either
        # (remove the in-flight entry directly, and no FIFO message_processed callback).
        expect(subject).not_to receive(:processor_done)

        expect { subject.send(:assign, queue, sqs_msg) }.not_to raise_error

        expect(subject.send(:busy)).to eq(0)
      end

      it 'does not run the FIFO message_processed callback' do
        # The message was never processed, so the rejection rollback must
        # remove the in-flight entry directly and never reach the FIFO bookkeeping - even for a
        # FIFO queue. Guards against a refactor routing rollback through
        # processor_done.
        allow(sqs_queue).to receive(:fifo?).and_return(true)
        expect(polling_strategy).not_to receive(:message_processed)

        subject.send(:assign, queue, sqs_msg)

        expect(subject.send(:busy)).to eq(0)
      end

      it 'releases the message by setting its visibility timeout to 0' do
        subject.send(:assign, queue, sqs_msg)

        expect(released_entries).to eq([{ id: '0', receipt_handle: 'm1', visibility_timeout: 0 }])
      end

      it 'does not raise when the release fails' do
        allow(client).to receive(:change_message_visibility_batch).and_raise('change visibility failed')
        allow(Shoryuken.logger).to receive(:error)

        expect { subject.send(:assign, queue, sqs_msg) }.not_to raise_error

        expect(subject.send(:busy)).to eq(0)
      end
    end
  end

  describe '#in_flight_messages' do
    let(:sqs_msg) { double(Shoryuken::Message, message_id: SecureRandom.uuid) }
    let(:other_msg) { double(Shoryuken::Message, message_id: SecureRandom.uuid) }
    let(:sqs_queue) { double(Shoryuken::Queue, fifo?: false) }

    before do
      # one dispatch, then stop the dispatch loop
      allow(subject).to receive(:running?).and_return(true, true, true, false)
      allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
    end

    it 'holds a message only while it is processed' do
      allow(fetcher).to receive(:fetch).and_return([sqs_msg])
      in_flight = nil
      allow(Shoryuken::Processor).to receive(:process) { in_flight = subject.in_flight_messages }

      subject.start

      expect(in_flight).to eq([sqs_msg])
      expect(subject.in_flight_messages).to eq([])
    end

    it 'holds every message of a batch while it is processed' do
      TestWorker.get_shoryuken_options['batch'] = true
      allow(fetcher).to receive(:fetch).and_return([sqs_msg, other_msg])
      in_flight = nil
      allow(Shoryuken::Processor).to receive(:process) { in_flight = subject.in_flight_messages }

      subject.start

      expect(in_flight).to eq([sqs_msg, other_msg])
      expect(subject.in_flight_messages).to eq([])
    end

    it 'drops a message when processing raises' do
      allow(fetcher).to receive(:fetch).and_return([sqs_msg])
      allow(Shoryuken::Processor).to receive(:process).and_raise('processing failed')

      subject.start

      expect(Shoryuken::Processor).to have_received(:process)
      expect(subject.in_flight_messages).to eq([])
    end

    context 'when the executor rejects the worker post' do
      # Runs the dispatch, rejects the worker post it makes
      let(:executor) do
        double('executor', running?: true).tap do |rejecting_executor|
          posts = 0
          allow(rejecting_executor).to receive(:post) do |&block|
            posts += 1
            raise Concurrent::RejectedExecutionError if posts == 2

            block.call
          end
        end
      end

      it 'does not hold the message' do
        allow(fetcher).to receive(:fetch).and_return([sqs_msg])
        allow(subject).to receive(:release)

        subject.start

        expect(subject).to have_received(:release).with(sqs_msg)
        expect(subject.in_flight_messages).to eq([])
      end
    end
  end

  describe '#killed_messages' do
    let(:sqs_msg) { double(Shoryuken::Message, message_id: SecureRandom.uuid) }
    let(:other_msg) { double(Shoryuken::Message, message_id: SecureRandom.uuid) }
    let(:sqs_queue) { double(Shoryuken::Queue, fifo?: false) }
    let(:workers) { [] }
    # Runs the dispatch inline and each worker in its own thread, so a spec can kill it
    let(:executor) do
      double('executor', running?: true).tap do |threaded_executor|
        allow(threaded_executor).to receive(:post) do |&block|
          subject.in_flight_messages.empty? ? block.call : workers << Thread.new(&block)
        end
      end
    end

    before do
      allow(subject).to receive(:running?).and_return(true, true, true, false)
      allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
      allow(fetcher).to receive(:fetch).and_return([sqs_msg])
    end

    def kill_worker_in_job
      started = Queue.new
      allow(Shoryuken::Processor).to receive(:process) do
        started << true
        sleep
      end

      subject.start
      started.pop
      workers.first.kill.join
    end

    it 'holds the message of a worker killed in its job' do
      kill_worker_in_job

      expect(subject.killed_messages).to eq([sqs_msg])
      expect(subject.in_flight_messages).to eq([])
    end

    it 'holds every message of a killed batch worker' do
      TestWorker.get_shoryuken_options['batch'] = true
      allow(fetcher).to receive(:fetch).and_return([sqs_msg, other_msg])

      kill_worker_in_job

      expect(subject.killed_messages).to eq([sqs_msg, other_msg])
    end

    it 'does not hold the message of a worker whose job finished' do
      allow(Shoryuken::Processor).to receive(:process)

      subject.start
      workers.each(&:join)

      expect(Shoryuken::Processor).to have_received(:process)
      expect(subject.killed_messages).to eq([])
    end

    it 'does not hold the message of a worker whose job raised' do
      allow(Shoryuken::Processor).to receive(:process).and_raise('processing failed')

      subject.start
      workers.each(&:join)

      expect(Shoryuken::Processor).to have_received(:process)
      expect(subject.killed_messages).to eq([])
    end
  end

  describe '#release' do
    it 'sends one request per queue and per 10 messages' do
      messages = Array.new(12) { |i| build_message("a#{i}", 'queue-a') } + [build_message('b0', 'queue-b')]

      subject.release(messages)

      expect(client).to have_received(:change_message_visibility_batch).exactly(3).times
      first_entries = Array.new(10) { |i| { id: i.to_s, receipt_handle: "a#{i}", visibility_timeout: 0 } }
      second_entries = Array.new(2) { |i| { id: i.to_s, receipt_handle: "a#{i + 10}", visibility_timeout: 0 } }
      expect(client).to have_received(:change_message_visibility_batch).with(queue_url: 'queue-a', entries: first_entries)
      expect(client).to have_received(:change_message_visibility_batch).with(queue_url: 'queue-a', entries: second_entries)
      expect(client).to have_received(:change_message_visibility_batch)
        .with(queue_url: 'queue-b', entries: [{ id: '0', receipt_handle: 'b0', visibility_timeout: 0 }])
    end

    it 'logs each message the batch request fails to release' do
      messages = [build_message('a0', 'queue-a'), build_message('a1', 'queue-a')]
      failure = double(id: '1', code: 'InternalError', message: 'failed')
      allow(client).to receive(:change_message_visibility_batch).and_return(double(failed: [failure]))
      allow(Shoryuken.logger).to receive(:error)

      subject.release(messages)

      expect(Shoryuken.logger).to have_received(:error).once do |&block|
        expect(block.call).to include(messages[1].message_id, 'InternalError')
      end
    end

    %w[ReceiptHandleIsInvalid MessageNotInflight InvalidParameterValue].each do |code|
      it "logs a message no longer in flight (#{code}) at debug level, not as an error" do
        messages = [build_message('a0', 'queue-a')]
        failure = double(id: '0', code: code, message: 'not in flight')
        allow(client).to receive(:change_message_visibility_batch).and_return(double(failed: [failure]))
        allow(Shoryuken.logger).to receive(:error)
        allow(Shoryuken.logger).to receive(:debug)

        subject.release(messages)

        expect(Shoryuken.logger).not_to have_received(:error)
        expect(Shoryuken.logger).to have_received(:debug).once do |&block|
          expect(block.call).to include(messages[0].message_id, code)
        end
      end
    end

    it 'releases the other queues when the request for one queue fails' do
      allow(client).to receive(:change_message_visibility_batch)
        .with(hash_including(queue_url: 'queue-a'))
        .and_raise('failed')
      allow(Shoryuken.logger).to receive(:error)

      subject.release([build_message('a0', 'queue-a'), build_message('b0', 'queue-b')])

      expect(client).to have_received(:change_message_visibility_batch).with(hash_including(queue_url: 'queue-b'))
      expect(Shoryuken.logger).to have_received(:error)
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
        subject.send(:processor_done, queue, double(Shoryuken::Message), true)
      end
    end

    context 'when queue.fifo? is false' do
      it 'does not call message_processed on strategy' do
        expect(sqs_queue).to receive(:fifo?).and_return(false)
        expect(polling_strategy).to_not receive(:message_processed)
        subject.send(:processor_done, queue, double(Shoryuken::Message), true)
      end
    end
  end

  describe '#handle_dispatch_error' do
    let(:error) { StandardError.new('boom') }

    context 'when running under the CLI (server mode)' do
      before { allow(Shoryuken).to receive(:server?).and_return(true) }

      it 'stops the manager and signals the process to shut down' do
        expect(Process).to receive(:kill).with('USR1', Process.pid)

        subject.send(:handle_dispatch_error, error)

        expect(subject.running?).to be false
        expect(subject.failed?).to be true
      end
    end

    context 'when embedded (no Runner)' do
      before { allow(Shoryuken).to receive(:server?).and_return(false) }

      it 'stops the manager without signalling the process' do
        expect(Process).not_to receive(:kill)

        subject.send(:handle_dispatch_error, error)

        expect(subject.running?).to be false
        expect(subject.failed?).to be true
      end
    end
  end

  describe '#failed?' do
    it 'returns false when the manager is stopped without a dispatch error' do
      allow(executor).to receive(:running?).and_return(false)
      subject.stop_new_dispatching

      expect(subject.failed?).to be false
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
