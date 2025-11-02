# frozen_string_literal: true

require 'active_job'
require 'shared_examples_for_active_job'
require 'shoryuken/extensions/active_job_adapter'
require 'shoryuken/extensions/active_job_extensions'

RSpec.describe 'ActiveJob Continuation support' do
  let(:adapter) { ActiveJob::QueueAdapters::ShoryukenAdapter.new }
  let(:job) do
    job = TestJob.new
    job.sqs_send_message_parameters = {}
    job
  end
  let(:queue) { double('Queue', fifo?: false) }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(job.queue_name).and_return(queue)
    allow(Shoryuken).to receive(:register_worker)
  end

  describe '#stopping?' do
    context 'when Launcher is not initialized' do
      it 'returns false' do
        runner = instance_double(Shoryuken::Runner, launcher: nil)
        allow(Shoryuken::Runner).to receive(:instance).and_return(runner)

        expect(adapter.stopping?).to be false
      end
    end

    context 'when Launcher is initialized' do
      let(:runner) { instance_double(Shoryuken::Runner) }
      let(:launcher) { instance_double(Shoryuken::Launcher) }

      before do
        allow(Shoryuken::Runner).to receive(:instance).and_return(runner)
        allow(runner).to receive(:launcher).and_return(launcher)
      end

      it 'returns false when not stopping' do
        allow(launcher).to receive(:stopping?).and_return(false)
        expect(adapter.stopping?).to be false
      end

      it 'returns true when stopping' do
        allow(launcher).to receive(:stopping?).and_return(true)
        expect(adapter.stopping?).to be true
      end
    end
  end

  describe '#enqueue_at with past timestamps' do
    let(:past_timestamp) { Time.current.to_f - 60 } # 60 seconds ago

    it 'enqueues with negative delay_seconds when timestamp is in the past' do
      expect(queue).to receive(:send_message) do |hash|
        expect(hash[:delay_seconds]).to be <= 0
        expect(hash[:delay_seconds]).to be >= -61 # Allow for rounding and timing
      end

      adapter.enqueue_at(job, past_timestamp)
    end

    it 'does not raise an error for past timestamps' do
      allow(queue).to receive(:send_message)

      expect { adapter.enqueue_at(job, past_timestamp) }.not_to raise_error
    end
  end

  describe '#enqueue_at with future timestamps' do
    let(:future_timestamp) { Time.current.to_f + 60 } # 60 seconds from now

    it 'enqueues with delay_seconds when timestamp is in the future' do
      expect(queue).to receive(:send_message) do |hash|
        expect(hash[:delay_seconds]).to be > 0
        expect(hash[:delay_seconds]).to be <= 60
      end

      adapter.enqueue_at(job, future_timestamp)
    end
  end

  describe '#enqueue_at with current timestamp' do
    let(:current_timestamp) { Time.current.to_f }

    it 'enqueues with delay_seconds close to 0' do
      expect(queue).to receive(:send_message) do |hash|
        expect(hash[:delay_seconds]).to be_between(-1, 1) # Allow for timing/rounding
      end

      adapter.enqueue_at(job, current_timestamp)
    end
  end

  describe 'retry_on with zero wait' do
    it 'allows immediate retries through continuation mechanism' do
      # Simulate a job with retry_on configuration that uses zero wait
      past_timestamp = Time.current.to_f - 1

      expect(queue).to receive(:send_message) do |hash|
        # Negative delay for past timestamp - SQS will handle immediate delivery
        expect(hash[:delay_seconds]).to be <= 0
      end

      adapter.enqueue_at(job, past_timestamp)
    end
  end
end
