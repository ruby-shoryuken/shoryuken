# frozen_string_literal: true

require 'active_job'
require 'active_job/extensions'
require 'active_job/queue_adapters/shoryuken_adapter'

RSpec.describe Shoryuken::ActiveJob::JobWrapper do
  subject { described_class.new }

  describe '#perform' do
    let(:sqs_msg) do
      double Shoryuken::Message, attributes: { 'ApproximateReceiveCount' => receive_count }, message_attributes: {}
    end

    context 'when the message is received for the first time' do
      let(:receive_count) { '1' }

      it 'keeps the serialized executions' do
        expect(ActiveJob::Base).to receive(:execute).with(
          { 'arguments' => [1], 'executions' => 2, 'shoryuken_sqs_message' => sqs_msg }
        )

        subject.perform sqs_msg, { 'arguments' => [1], 'executions' => 2 }
      end
    end

    context 'when SQS redelivers the message' do
      let(:receive_count) { '42' }

      it 'adds the past receives to the serialized executions' do
        expect(ActiveJob::Base).to receive(:execute).with(
          { 'arguments' => [1], 'executions' => 43, 'shoryuken_sqs_message' => sqs_msg }
        )

        subject.perform sqs_msg, { 'arguments' => [1], 'executions' => 2 }
      end

      it 'counts missing serialized executions as 0' do
        expect(ActiveJob::Base).to receive(:execute).with(
          { 'arguments' => [1], 'executions' => 41, 'shoryuken_sqs_message' => sqs_msg }
        )

        subject.perform sqs_msg, { 'arguments' => [1] }
      end

      it 'counts nil serialized executions as 0' do
        expect(ActiveJob::Base).to receive(:execute).with(
          { 'arguments' => [1], 'executions' => 41, 'shoryuken_sqs_message' => sqs_msg }
        )

        subject.perform sqs_msg, { 'arguments' => [1], 'executions' => nil }
      end
    end

    context 'when the job is enqueued again from the worker' do
      let(:job_class) do
        Class.new(ActiveJob::Base) do
          def self.name
            'JobWrapperSpecJob'
          end

          def perform(options = {})
            enqueue(options.symbolize_keys)
          end
        end
      end

      let(:adapter) { instance_double(ActiveJob::QueueAdapters::ShoryukenAdapter) }
      let(:tenant) { { string_value: 'acme', data_type: 'String' } }
      let(:enqueued_parameters) { [] }

      let(:sqs_msg) do
        double(
          Shoryuken::Message,
          attributes: {
            'ApproximateReceiveCount' => '1',
            'MessageGroupId' => 'order-42',
            'MessageDeduplicationId' => 'dedup-1'
          },
          message_attributes: {
            'tenant' => Aws::SQS::Types::MessageAttributeValue.new(**tenant, string_list_values: []),
            'shoryuken_class' => { string_value: described_class.to_s, data_type: 'String' }
          }
        )
      end

      before do
        stub_const('JobWrapperSpecJob', job_class)
        allow(job_class).to receive(:queue_adapter).and_return(adapter)
        allow(adapter).to receive(:enqueue) do |job|
          enqueued_parameters << job.sqs_send_message_parameters.dup
          enqueued_parameters << job.serialize
        end
      end

      it 'keeps the group id and the custom attributes of the received message' do
        subject.perform sqs_msg, job_class.new.serialize

        expect(enqueued_parameters.first).to eq(
          message_group_id: 'order-42',
          message_attributes: { 'tenant' => tenant }
        )
      end

      it 'does not keep the deduplication id' do
        subject.perform sqs_msg, job_class.new.serialize

        expect(enqueued_parameters.first).not_to have_key(:message_deduplication_id)
      end

      it 'does not keep the adapter-owned attributes' do
        subject.perform sqs_msg, job_class.new.serialize

        expect(enqueued_parameters.first[:message_attributes]).not_to have_key('shoryuken_class')
      end

      it 'does not add the received message to the serialized job' do
        subject.perform sqs_msg, job_class.new.serialize

        expect(enqueued_parameters.last).not_to have_key('shoryuken_sqs_message')
      end

      it 'lets values given on re-enqueue win over the received ones' do
        other = { 'tenant' => { string_value: 'other', data_type: 'String' } }

        subject.perform sqs_msg, job_class.new({ 'message_group_id' => 'other', 'message_attributes' => other }).serialize

        expect(enqueued_parameters.first).to eq(message_group_id: 'other', message_attributes: other)
      end

      context 'when the received message has neither a group id nor custom message attributes' do
        let(:sqs_msg) do
          double(
            Shoryuken::Message,
            attributes: { 'ApproximateReceiveCount' => '1' },
            message_attributes: {
              'shoryuken_class' => { string_value: described_class.to_s, data_type: 'String' }
            }
          )
        end

        it 'adds no SQS parameters to the job' do
          subject.perform sqs_msg, job_class.new.serialize

          expect(enqueued_parameters.first).to eq({})
        end
      end
    end
  end
end
