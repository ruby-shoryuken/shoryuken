# frozen_string_literal: true

require 'shared_examples_for_active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_support/core_ext/numeric/time'

RSpec.describe ActiveJob::QueueAdapters::ShoryukenAdapter do
  include_examples 'active_job_adapters'

  describe '#enqueue_after_transaction_commit?' do
    it 'returns true to support Rails 7.2+ transaction commit behavior' do
      adapter = described_class.new
      expect(adapter.enqueue_after_transaction_commit?).to eq(true)
    end
  end

  describe 'enqueueing the same job instance twice' do
    let(:adapter) { described_class.new }
    let(:fifo) { false }
    let(:queue) { double 'Queue', fifo?: fifo }
    let(:sent) { [] }
    let(:job) { TestJob.new(1) }

    before do
      allow(Shoryuken::Client).to receive(:queues).with(job.queue_name).and_return(queue)
      # Like Shoryuken::Queue#send_message, which changes the parameters it is given
      allow(queue).to receive(:send_message) do |params|
        params[:message_body] = JSON.dump(params[:message_body])
        if fifo
          params[:message_group_id] ||= Shoryuken::Queue::MESSAGE_GROUP_ID
          params[:message_deduplication_id] ||= Digest::SHA256.hexdigest(params[:message_body])
        end
        sent << params.dup
      end
      allow(job).to receive(:queue_adapter).and_return(adapter)
    end

    def sent_arguments
      JSON.parse(sent.last[:message_body])['arguments']
    end

    it 'sends the current body and no delay when the job is no longer scheduled' do
      job.enqueue(wait: 60)
      job.arguments = [2]
      job.scheduled_at = nil
      job.enqueue

      expect(sent_arguments).to eq([2])
      expect(sent.last).not_to have_key(:delay_seconds)
    end

    it 'keeps the parameters set on the job' do
      job.enqueue(message_attributes: { 'tracer' => { string_value: 'abc', data_type: 'String' } })
      job.arguments = [2]
      job.enqueue

      expect(sent.last[:message_attributes].keys).to contain_exactly('tracer', 'shoryuken_class')
    end

    it 'sends the current body when the job is bulk enqueued again' do
      entries = []
      allow(queue).to receive(:send_messages) do |params|
        entries.concat(params[:entries])
        double(successful: [double(id: '0')])
      end
      adapter.enqueue_all([job])
      job.arguments = [2]
      adapter.enqueue_all([job])

      expect(entries.last[:message_body]['arguments']).to eq([2])
    end

    context 'when fifo' do
      let(:fifo) { true }

      it 'sends a deduplication id of the current body and keeps the message group id set on the job' do
        job.enqueue(message_group_id: 'group')
        job.arguments = [2]
        job.enqueue

        expect(sent.last[:message_deduplication_id]).to eq(
          Digest::SHA256.hexdigest(JSON.dump(JSON.parse(sent.last[:message_body]).except('job_id', 'enqueued_at')))
        )
        expect(sent.last[:message_deduplication_id]).not_to eq(sent.first[:message_deduplication_id])
        expect(sent.last[:message_group_id]).to eq('group')
      end

      it 'sends the queue deduplication id of the current body when the adapter does not set one' do
        Shoryuken.active_job_fifo_message_deduplication = false
        job.enqueue
        job.arguments = [2]
        job.enqueue

        expect(sent.last[:message_deduplication_id]).to eq(Digest::SHA256.hexdigest(sent.last[:message_body]))
      end

      it 'keeps a deduplication id set on the job' do
        job.enqueue(message_deduplication_id: 'dedup')
        job.arguments = [2]
        job.enqueue

        expect(sent.last[:message_deduplication_id]).to eq('dedup')
      end

      it 'applies a parameter changed on the job after the previous send' do
        job.enqueue(message_group_id: 'group1')
        job.sqs_send_message_parameters[:message_group_id] = 'group2'
        job.arguments = [2]
        job.enqueue

        expect(sent.last[:message_group_id]).to eq('group2')
        expect(sent_arguments).to eq([2])
      end

      it 'keeps the message group id set on the job after a bulk enqueue' do
        allow(queue).to receive(:send_messages).and_return(double(successful: [double(id: '0')]))
        job.sqs_send_message_parameters = { message_group_id: 'group' }
        adapter.enqueue_all([job])
        job.arguments = [2]
        job.enqueue

        expect(sent.last[:message_group_id]).to eq('group')
        expect(sent_arguments).to eq([2])
      end
    end
  end

  describe '.instance' do
    it 'returns the same instance (singleton pattern)' do
      instance1 = described_class.instance
      instance2 = described_class.instance
      expect(instance1).to be(instance2)
    end

    it 'returns a ShoryukenAdapter instance' do
      expect(described_class.instance).to be_a(described_class)
    end
  end
end