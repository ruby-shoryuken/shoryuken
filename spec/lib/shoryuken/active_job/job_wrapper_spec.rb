# frozen_string_literal: true

require 'active_job'
require 'active_job/extensions'
require 'active_job/queue_adapters/shoryuken_adapter'

RSpec.describe Shoryuken::ActiveJob::JobWrapper do
  subject { described_class.new }

  describe '#perform' do
    let(:sqs_msg) { double Shoryuken::Message, attributes: { 'ApproximateReceiveCount' => receive_count } }

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
  end
end