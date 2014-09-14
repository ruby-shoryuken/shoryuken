require 'spec_helper'

describe Shoryuken::Fetcher do
  let(:manager)   { double Shoryuken::Manager }
  let(:sqs_queue) { double 'sqs_queue' }
  let(:queue)     { 'shoryuken' }
  let(:sqs_msg)   { double 'SQS msg'}

  subject { described_class.new(manager) }

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  describe '#fetch' do
    it 'calls skip_and_dispatch when not found' do
      allow(sqs_queue).to receive(:receive_message).and_return(nil)

      expect(manager).to receive(:work_not_found!).with(queue)
      expect(manager).to receive(:dispatch)

      subject.fetch(queue)
    end

    it 'assigns messages' do
      allow(sqs_queue).to receive(:receive_message).and_return(sqs_msg)

      expect(manager).to receive(:assign).with(queue, sqs_msg)

      subject.fetch(queue)
    end
  end
end
