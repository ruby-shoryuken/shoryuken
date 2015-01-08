require 'spec_helper'

describe Shoryuken::Topic do
  let(:sns) { Aws::SNS::Client.new stub_responses: true }
  let(:topic_arn) { 'arn:aws:sns:us-east-1:0987654321:shoryuken' }
  let(:topic_name) { 'shoryuken' }

  before do
    Shoryuken::Client.account_id = '0987654321'
    Aws.config = { region: 'us-east-1' }
  end

  subject { described_class.new(topic_name, sns) }

  describe '#send_message' do
    it 'enqueues a message' do
      sns.stub_responses(:publish, { message_id: 'msg1' })
      expect(sns).to receive(:publish).with(topic_arn: topic_arn, message: 'test')

      subject.send_message('test')
    end

    it 'parses as JSON by default' do
      msg = { field: 'test', other_field: 'other' }

      sns.stub_responses(:publish, { message_id: 'msg2' })
      expect(sns).to receive(:publish).with(topic_arn: topic_arn, message: JSON.dump(msg))

      subject.send_message(msg)
    end
  end
end
