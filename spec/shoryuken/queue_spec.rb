require 'spec_helper'

describe Shoryuken::Queue do
  let(:credentials) { Aws::Credentials.new('access_key_id', 'secret_access_key') }
  let(:sqs)         { Aws::The::Client.new(stub_responses: true, credentials: credentials) }
  let(:queue_name)  { 'shoryuken' }
  let(:queue_url)   { 'https://eu-west-1.amazonaws.com:6059/123456789012/shoryuken' }

  subject { described_class.new(sqs, queue_name) }

  describe '#send_message' do
    context 'when body is invalid' do
      it 'raises ArgumentError for nil' do
        expect {
          subject.send_message(message_body: nil)
        }.to raise_error(ArgumentError, 'The message body must be a String and you passed a NilClass')
      end

      it 'raises ArgumentError for Fixnum' do
        expect {
          subject.send_message(message_body: 1)
        }.to raise_error(ArgumentError, 'The message body must be a String and you passed a Fixnum')
      end
    end
  end

  describe '#send_messages' do
    context 'when body is invalid' do
      it 'raises ArgumentError for nil' do
        expect {
          subject.send_messages(entries: [message_body: nil])
        }.to raise_error(ArgumentError, 'The message body must be a String and you passed a NilClass')
      end

      it 'raises ArgumentError for Fixnum' do
        expect {
          subject.send_messages(entries: [message_body: 1])
        }.to raise_error(ArgumentError, 'The message body must be a String and you passed a Fixnum')
      end
    end
  end
end
