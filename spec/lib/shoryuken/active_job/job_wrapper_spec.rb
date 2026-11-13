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
        expect(ActiveJob::Base).to receive(:execute).with({ 'arguments' => [1], 'executions' => 2 })

        subject.perform sqs_msg, { 'arguments' => [1], 'executions' => 2 }
      end
    end

    context 'when SQS redelivers the message' do
      let(:receive_count) { '42' }

      it 'adds the past receives to the serialized executions' do
        expect(ActiveJob::Base).to receive(:execute).with({ 'arguments' => [1], 'executions' => 43 })

        subject.perform sqs_msg, { 'arguments' => [1], 'executions' => 2 }
      end

      it 'counts missing serialized executions as 0' do
        expect(ActiveJob::Base).to receive(:execute).with({ 'arguments' => [1], 'executions' => 41 })

        subject.perform sqs_msg, { 'arguments' => [1] }
      end

      it 'counts nil serialized executions as 0' do
        expect(ActiveJob::Base).to receive(:execute).with({ 'arguments' => [1], 'executions' => 41 })

        subject.perform sqs_msg, { 'arguments' => [1], 'executions' => nil }
      end
    end

    context 'when the message has a group id and custom message attributes' do
      let(:job_class) do
        Class.new(ActiveJob::Base) do
          def self.name
            'JobWrapperSpecJob'
          end

          def perform
            self.class.received_parameters = sqs_send_message_parameters.dup
          end

          class << self
            attr_accessor :received_parameters
          end
        end
      end

      let(:tenant) { { string_value: 'acme', data_type: 'String' } }

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

      before { stub_const('JobWrapperSpecJob', job_class) }

      it 'keeps the group id and the custom attributes in the job SQS parameters' do
        subject.perform sqs_msg, job_class.new.serialize

        expect(job_class.received_parameters).to eq(
          message_group_id: 'order-42',
          message_attributes: { 'tenant' => tenant }
        )
      end

      it 'does not keep the deduplication id' do
        subject.perform sqs_msg, job_class.new.serialize

        expect(job_class.received_parameters).not_to have_key(:message_deduplication_id)
      end

      it 'does not keep the adapter-owned attributes' do
        subject.perform sqs_msg, job_class.new.serialize

        expect(job_class.received_parameters[:message_attributes]).not_to have_key('shoryuken_class')
      end

      it 'does not add the parameters to the serialized job' do
        job_class.class_eval do
          def perform
            self.class.received_parameters = serialize
          end
        end

        subject.perform sqs_msg, job_class.new.serialize

        expect(job_class.received_parameters).not_to have_key('shoryuken_sqs_send_message_parameters')
      end

      it 'lets values given on re-enqueue win over the received ones' do
        job_class.class_eval do
          def perform
            enqueue(message_group_id: 'other')
          end
        end
        adapter = instance_double(ActiveJob::QueueAdapters::ShoryukenAdapter)
        allow(job_class).to receive(:queue_adapter).and_return(adapter)
        allow(adapter).to receive(:enqueue) { |job| job_class.received_parameters = job.sqs_send_message_parameters }

        subject.perform sqs_msg, job_class.new.serialize

        expect(job_class.received_parameters).to include(
          message_group_id: 'other',
          message_attributes: { 'tenant' => tenant }
        )
      end
    end

    context 'when the message has neither a group id nor custom message attributes' do
      let(:receive_count) { '1' }

      it 'passes no SQS parameters to the job' do
        expect(ActiveJob::Base).to receive(:execute).with({ 'arguments' => [1], 'executions' => 0 })

        subject.perform sqs_msg, { 'arguments' => [1] }
      end
    end
  end
end
