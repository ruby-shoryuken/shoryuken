require 'spec_helper'

describe Shoryuken::Processor do
  let(:manager) { double Shoryuken::Manager }
  let(:queue)   { double 'Queue' }
  let(:sqs_msg) { double 'SQS msg' }

  subject { described_class.new(manager) }

  describe '#process' do
    class HelloWorker1
      def perform(sqs_msg); end
    end

    class HelloWorker2
      def perform(sqs_msg, firstname, lastname); end
    end

    it 'calls worker' do
      expect(manager).to receive(:processor_done).with(subject)

      expect_any_instance_of(HelloWorker1).to receive(:perform).with(sqs_msg)

      subject.process(queue, sqs_msg, { 'class' => 'HelloWorker1', 'args' => [] })
    end

    it 'calls worker passing args' do
      firstname, lastname = %w[Pablo Cantero]

      expect(manager).to receive(:processor_done).with(subject)

      expect_any_instance_of(HelloWorker2).to receive(:perform).with(sqs_msg, firstname, lastname)

      subject.process(queue, sqs_msg, { 'class' => 'HelloWorker2', 'args' => [firstname, lastname] })
    end
  end
end
