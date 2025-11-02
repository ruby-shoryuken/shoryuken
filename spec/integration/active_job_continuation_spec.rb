# frozen_string_literal: true

require 'securerandom'
require 'active_job'
require 'shoryuken/extensions/active_job_adapter'
require 'shoryuken/extensions/active_job_extensions'

# Only run these tests if ActiveJob::Continuable is available (Rails 8.1+)
if defined?(ActiveJob::Continuable)
  RSpec.describe 'ActiveJob Continuations Integration' do
    # Test job that uses ActiveJob Continuations
    class ContinuableTestJob < ActiveJob::Base
      include ActiveJob::Continuable

      queue_as :default

      class_attribute :executions_log, default: []
      class_attribute :checkpoints_reached, default: []

      def perform(max_iterations: 10)
        self.class.executions_log << { execution: executions, started_at: Time.current }

        step :initialize_work do
          self.class.checkpoints_reached << "initialize_work_#{executions}"
        end

        step :process_items, start: cursor || 0 do
          (cursor..max_iterations).each do |i|
            self.class.checkpoints_reached << "processing_item_#{i}"

            # Check if we should stop (checkpoint)
            checkpoint

            # Simulate some work
            sleep 0.01

            # Advance cursor
            cursor.advance!
          end
        end

        step :finalize_work do
          self.class.checkpoints_reached << 'finalize_work'
        end

        self.class.executions_log.last[:completed] = true
      end
    end

    describe 'stopping? method (unit tests)' do
      it 'returns false when launcher is not initialized' do
        adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
        expect(adapter.stopping?).to be false
      end

      it 'returns true when launcher is stopping' do
        launcher = Shoryuken::Launcher.new
        runner = Shoryuken::Runner.instance
        runner.instance_variable_set(:@launcher, launcher)

        adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
        expect(adapter.stopping?).to be false

        launcher.instance_variable_set(:@stopping, true)
        expect(adapter.stopping?).to be true
      end
    end

    describe 'timestamp handling for continuation retries' do
      it 'handles past timestamps for continuation retries' do
        adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
        job = ContinuableTestJob.new
        job.sqs_send_message_parameters = {}

        # Mock the queue
        queue = instance_double(Shoryuken::Queue, fifo?: false)
        allow(Shoryuken::Client).to receive(:queues).and_return(queue)
        allow(Shoryuken).to receive(:register_worker)
        allow(queue).to receive(:send_message) do |params|
          # Verify past timestamp results in immediate delivery (delay_seconds <= 0)
          expect(params[:delay_seconds]).to be <= 0
        end

        # Enqueue with past timestamp (simulating continuation retry)
        past_timestamp = Time.current.to_f - 60
        adapter.enqueue_at(job, past_timestamp)
      end
    end

    describe 'enqueue_at with continuation timestamps (unit tests)' do
      let(:adapter) { ActiveJob::QueueAdapters::ShoryukenAdapter.new }
      let(:job) do
        job = ContinuableTestJob.new
        job.sqs_send_message_parameters = {}
        job
      end
      let(:queue) { instance_double(Shoryuken::Queue, fifo?: false) }

      before do
        allow(Shoryuken::Client).to receive(:queues).and_return(queue)
        allow(Shoryuken).to receive(:register_worker)
        @sent_messages = []
        allow(queue).to receive(:send_message) do |params|
          @sent_messages << params
        end
      end

      it 'accepts past timestamps without error' do
        past_timestamp = Time.current.to_f - 30

        expect {
          adapter.enqueue_at(job, past_timestamp)
        }.not_to raise_error

        expect(@sent_messages.size).to eq(1)
        expect(@sent_messages.first[:delay_seconds]).to be <= 0
      end

      it 'accepts current timestamp' do
        current_timestamp = Time.current.to_f

        expect {
          adapter.enqueue_at(job, current_timestamp)
        }.not_to raise_error

        expect(@sent_messages.size).to eq(1)
        expect(@sent_messages.first[:delay_seconds]).to be_between(-1, 1)
      end

      it 'accepts future timestamp' do
        future_timestamp = Time.current.to_f + 30

        expect {
          adapter.enqueue_at(job, future_timestamp)
        }.not_to raise_error

        expect(@sent_messages.size).to eq(1)
        expect(@sent_messages.first[:delay_seconds]).to be > 0
        expect(@sent_messages.first[:delay_seconds]).to be <= 30
      end
    end
  end
else
  RSpec.describe 'ActiveJob Continuations Integration' do
    it 'is skipped because ActiveJob::Continuable is not available (Rails < 8.1)' do
      skip 'ActiveJob::Continuable not available in this Rails version'
    end
  end
end
