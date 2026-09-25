# frozen_string_literal: true

require 'shared_examples_for_active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter do
  include_examples 'active_job_adapters'

  let(:options) { {} }
  let(:error_handler) { -> {} }
  let(:success_handler) { -> {} }

  before do
    allow(Concurrent).to receive(:global_io_executor).and_return(Concurrent::ImmediateExecutor.new)
  end

  subject { described_class.new(success_handler, error_handler) }

  context 'when success' do
    it 'calls success_handler' do
      response = true
      allow(queue).to receive(:send_message).and_return(response)
      expect(success_handler).to receive(:call).with(response, job, options)

      subject.enqueue(job, options)
    end
  end

  context 'when failure' do
    it 'calls error_handler' do
      response = Aws::SQS::Errors::InternalError.new('error', 'error')

      allow(queue).to receive(:send_message).and_raise(response)
      expect(error_handler).to receive(:call).with(response, job, options).and_call_original

      subject.enqueue(job, options)
    end
  end

  describe '#wait_for_pending_sends' do
    # Use a real async executor (instead of the ImmediateExecutor stubbed above)
    # so sends are genuinely in-flight and the drain has something to wait for.
    let(:pool) { Concurrent::FixedThreadPool.new(2) }
    let(:success_handler) { ->(_response, _job, _options) {} }
    let(:error_handler) { ->(_error, _job, _options) {} }

    before do
      allow(Concurrent).to receive(:global_io_executor).and_return(pool)
      allow(Shoryuken).to receive(:register_worker)
    end

    after do
      pool.shutdown
      pool.wait_for_termination(5)
    end

    it 'returns true when there are no pending sends' do
      expect(subject.wait_for_pending_sends(1)).to be true
    end

    it 'blocks until an in-flight send completes' do
      completed = Concurrent::AtomicBoolean.new(false)
      allow(queue).to receive(:send_message) do
        sleep 0.3
        completed.make_true
        true
      end

      subject.enqueue(job, options)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(subject.wait_for_pending_sends(5)).to be true
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(completed.value).to be true
      expect(elapsed).to be >= 0.2
    end

    it 'returns false when sends do not finish within the timeout' do
      allow(queue).to receive(:send_message) do
        sleep 2
        true
      end

      subject.enqueue(job, options)

      expect(subject.wait_for_pending_sends(0.2)).to be false
    end

    it 'stops tracking sends once they resolve (no unbounded growth)' do
      allow(queue).to receive(:send_message).and_return(true)

      3.times { subject.enqueue(job, options) }
      expect(subject.wait_for_pending_sends(5)).to be true

      # Removal happens on the resolving thread, so poll the mutex-guarded set.
      mutex = subject.instance_variable_get(:@pending_sends_mutex)
      set = subject.instance_variable_get(:@pending_sends)
      50.times do
        break if mutex.synchronize { set.empty? }

        sleep 0.02
      end

      expect(mutex.synchronize { set.size }).to eq(0)
    end
  end
end