require 'spec_helper'

describe Shoryuken::Processor do
  let(:manager) { double Shoryuken::Manager }
  let(:queue)   { double 'Queue' }
  let(:sqs_msg) { double 'SQS msg' }

  subject { described_class.new(manager) }

  it 'calls worker' do
    expect(manager).to receive(:processor_done).with(subject)
    expect_any_instance_of(HelloWorker).to receive(:perform).with(sqs_msg)

    subject.process(queue, sqs_msg)
  end
end
