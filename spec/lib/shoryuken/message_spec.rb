# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Message do
  let(:client) { instance_double('Aws::SQS::Client') }
  let(:queue) { instance_double('Shoryuken::Queue', name: 'test-queue', url: 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue') }
  let(:data) do
    instance_double('Aws::SQS::Types::Message',
                    message_id: 'msg-123',
                    receipt_handle: 'handle-456',
                    md5_of_body: 'abcd1234',
                    body: '{"test": "data"}',
                    attributes: { 'ApproximateReceiveCount' => '1' },
                    md5_of_message_attributes: 'efgh5678',
                    message_attributes: { 'type' => 'test' })
  end

  subject { described_class.new(client, queue, data) }

  describe '#initialize' do
    it 'sets client, queue_url, queue_name, and data' do
      expect(subject.client).to eq(client)
      expect(subject.queue_url).to eq('https://sqs.us-east-1.amazonaws.com/123456789/test-queue')
      expect(subject.queue_name).to eq('test-queue')
      expect(subject.data).to eq(data)
    end
  end

  describe 'delegated methods' do
    it 'delegates message_id to data' do
      expect(subject.message_id).to eq('msg-123')
    end

    it 'delegates receipt_handle to data' do
      expect(subject.receipt_handle).to eq('handle-456')
    end

    it 'delegates md5_of_body to data' do
      expect(subject.md5_of_body).to eq('abcd1234')
    end

    it 'delegates body to data' do
      expect(subject.body).to eq('{"test": "data"}')
    end

    it 'delegates attributes to data' do
      expect(subject.attributes).to eq({ 'ApproximateReceiveCount' => '1' })
    end

    it 'delegates md5_of_message_attributes to data' do
      expect(subject.md5_of_message_attributes).to eq('efgh5678')
    end

    it 'delegates message_attributes to data' do
      expect(subject.message_attributes).to eq({ 'type' => 'test' })
    end
  end

  describe '#delete' do
    it 'calls delete_message on the client with correct parameters' do
      expect(client).to receive(:delete_message).with(
        queue_url: 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue',
        receipt_handle: 'handle-456'
      )

      subject.delete
    end
  end

  describe '#change_visibility' do
    it 'calls change_message_visibility on the client with merged parameters' do
      options = { visibility_timeout: 300 }

      expect(client).to receive(:change_message_visibility).with(hash_including(
        visibility_timeout: 300,
        queue_url: 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue',
        receipt_handle: 'handle-456'
      ))

      subject.change_visibility(options)
    end

    it 'merges queue_url and receipt_handle into provided options' do
      options = { visibility_timeout: 120, custom_param: 'value' }

      expect(client).to receive(:change_message_visibility).with(hash_including(
        visibility_timeout: 120,
        custom_param: 'value',
        queue_url: 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue',
        receipt_handle: 'handle-456'
      ))

      subject.change_visibility(options)
    end
  end

  describe '#visibility_timeout=' do
    it 'calls change_message_visibility on the client with the timeout' do
      expect(client).to receive(:change_message_visibility).with(
        queue_url: 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue',
        receipt_handle: 'handle-456',
        visibility_timeout: 600
      )

      subject.visibility_timeout = 600
    end
  end
end