require 'spec_helper'

describe Shoryuken::Fetcher do
  let(:manager) { double Shoryuken::Manager }
  let(:queue)   { double 'Queue' }
  let(:sqs_msg) { double 'SQS msg'}

  subject { described_class.new(manager) }

  before do
    allow(manager).to receive(:async).and_return(manager)
  end

  describe '#fetch' do
    it 'calls skip_and_dispatch when not found' do
      allow(queue).to receive(:receive_message).and_return(nil)

      expect(manager).to receive(:skip_and_dispatch).with(queue)

      subject.fetch(queue)
    end

    it 'assigns messages' do
      allow(queue).to receive(:receive_message).and_return(sqs_msg)

      expect(manager).to receive(:assign).with(queue, sqs_msg)

      subject.fetch(queue)
    end
  end
end
