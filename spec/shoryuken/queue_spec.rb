require 'spec_helper'

describe Shoryuken::Queue do
  let(:sqs) { Aws::SQS::Client.new stub_responses: true }
  let(:queue_name) { 'shoryuken' }
  let(:queue_url) { 'https://eu-west-1.amazonaws.com:6059/123456789012/shoryuken' }

  subject { described_class.new queue_name, sqs }

  before do
    sqs.stub_responses(:get_queue_url, { queue_url: queue_url }, { queue_url: 'xyz' })
  end

  describe '#send_message' do
    it 'enqueues a message' do
      sqs.stub_responses(:send_message, { message_id: 'msg1' })
      expect(sqs).to receive(:send_message).with(queue_url: queue_url, message_body: 'test')

      subject.send_message('test')
    end

    it 'enqueues a message with options' do
      expect(sqs).to receive(:send_message).with(queue_url: queue_url, message_body: 'test2', delay_seconds: 60)

      subject.send_message('test2', delay_seconds: 60)
    end

    it 'parsers as JSON by default' do
      msg = { field: 'test', other_field: 'other' }

      expect(sqs).to receive(:send_message).with(queue_url: queue_url, message_body: JSON.dump(msg))

      subject.send_message(msg)
    end

    it 'parsers as JSON by default and keep the options' do
      msg = { field: 'test', other_field: 'other' }

      expect(sqs).to receive(:send_message).with(
        queue_url: queue_url,
        message_body: JSON.dump(msg),
        delay_seconds: 60)

      subject.send_message(msg, delay_seconds: 60)
    end
  end

  describe '#visibility_timeout' do
    it 'memoizes visibility_timeout' do
      sqs.stub_responses(:get_queue_attributes,
        { attributes: { 'VisibilityTimeout' => '30' }},
        { attributes: { 'VisibilityTimeout' => '60' }})

      expect(subject.visibility_timeout).to eq 30
      expect(subject.visibility_timeout).to eq 30
    end
  end
end
