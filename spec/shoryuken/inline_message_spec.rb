require 'spec_helper'

RSpec.describe Shoryuken::InlineMessage do
  let(:body) { '{"message": "test"}' }
  let(:attributes) { { 'SentTimestamp' => '1234567890' } }
  let(:md5_of_body) { 'abc123def456' }
  let(:md5_of_message_attributes) { 'def456abc123' }
  let(:message_attributes) { { 'CustomAttribute' => { string_value: 'value', data_type: 'String' } } }
  let(:message_id) { 'msg-12345' }
  let(:receipt_handle) { 'receipt-handle-12345' }
  let(:delete) { nil }
  let(:queue_name) { 'test-queue' }

  describe '#new' do
    context 'with positional arguments' do
      subject do
        described_class.new(
          body: body,
          attributes: attributes,
          md5_of_body: md5_of_body,
          md5_of_message_attributes: md5_of_message_attributes,
          message_attributes: message_attributes,
          message_id: message_id,
          receipt_handle: receipt_handle,
          delete: delete,
          queue_name: queue_name
        )
      end

      it 'initializes with all attributes' do
        expect(subject.body).to eq(body)
        expect(subject.attributes).to eq(attributes)
        expect(subject.md5_of_body).to eq(md5_of_body)
        expect(subject.md5_of_message_attributes).to eq(md5_of_message_attributes)
        expect(subject.message_attributes).to eq(message_attributes)
        expect(subject.message_id).to eq(message_id)
        expect(subject.receipt_handle).to eq(receipt_handle)
        expect(subject.delete).to eq(delete)
        expect(subject.queue_name).to eq(queue_name)
      end
    end

    context 'with keyword arguments' do
      subject do
        described_class.new(
          body: body,
          attributes: attributes,
          md5_of_body: md5_of_body,
          md5_of_message_attributes: md5_of_message_attributes,
          message_attributes: message_attributes,
          message_id: message_id,
          receipt_handle: receipt_handle,
          delete: delete,
          queue_name: queue_name
        )
      end

      it 'initializes with all attributes' do
        expect(subject.body).to eq(body)
        expect(subject.attributes).to eq(attributes)
        expect(subject.md5_of_body).to eq(md5_of_body)
        expect(subject.md5_of_message_attributes).to eq(md5_of_message_attributes)
        expect(subject.message_attributes).to eq(message_attributes)
        expect(subject.message_id).to eq(message_id)
        expect(subject.receipt_handle).to eq(receipt_handle)
        expect(subject.delete).to eq(delete)
        expect(subject.queue_name).to eq(queue_name)
      end
    end

    context 'with nil values' do
      subject do
        described_class.new(
          body: body,
          attributes: nil,
          md5_of_body: nil,
          md5_of_message_attributes: nil,
          message_attributes: message_attributes,
          message_id: nil,
          receipt_handle: nil,
          delete: nil,
          queue_name: queue_name
        )
      end

      it 'handles nil values correctly' do
        expect(subject.body).to eq(body)
        expect(subject.attributes).to be_nil
        expect(subject.md5_of_body).to be_nil
        expect(subject.md5_of_message_attributes).to be_nil
        expect(subject.message_attributes).to eq(message_attributes)
        expect(subject.message_id).to be_nil
        expect(subject.receipt_handle).to be_nil
        expect(subject.delete).to be_nil
        expect(subject.queue_name).to eq(queue_name)
      end
    end

    context 'with minimal required attributes' do
      subject { described_class.new(body: body, queue_name: queue_name) }

      it 'initializes with only required attributes' do
        expect(subject.body).to eq(body)
        expect(subject.queue_name).to eq(queue_name)
        expect(subject.attributes).to be_nil
        expect(subject.md5_of_body).to be_nil
        expect(subject.md5_of_message_attributes).to be_nil
        expect(subject.message_attributes).to be_nil
        expect(subject.message_id).to be_nil
        expect(subject.receipt_handle).to be_nil
        expect(subject.delete).to be_nil
      end
    end
  end

  describe 'attribute accessors' do
    subject do
      described_class.new(
        body: body,
        attributes: attributes,
        md5_of_body: md5_of_body,
        md5_of_message_attributes: md5_of_message_attributes,
        message_attributes: message_attributes,
        message_id: message_id,
        receipt_handle: receipt_handle,
        delete: delete,
        queue_name: queue_name
      )
    end

    it 'provides read access to all attributes' do
      expect(subject.body).to eq(body)
      expect(subject.attributes).to eq(attributes)
      expect(subject.md5_of_body).to eq(md5_of_body)
      expect(subject.md5_of_message_attributes).to eq(md5_of_message_attributes)
      expect(subject.message_attributes).to eq(message_attributes)
      expect(subject.message_id).to eq(message_id)
      expect(subject.receipt_handle).to eq(receipt_handle)
      expect(subject.delete).to eq(delete)
      expect(subject.queue_name).to eq(queue_name)
    end

    it 'provides write access to all attributes' do
      new_body = '{"updated": "message"}'
      new_queue_name = 'updated-queue'

      subject.body = new_body
      subject.queue_name = new_queue_name

      expect(subject.body).to eq(new_body)
      expect(subject.queue_name).to eq(new_queue_name)
    end
  end

  describe 'struct behavior' do
    subject { described_class.new(body: body, queue_name: queue_name) }

    it 'behaves like a struct' do
      expect(subject).to be_a(Struct)
      expect(subject.class.superclass).to eq(Struct)
    end

    it 'supports array-like access' do
      expect(subject[0]).to eq(body)  # body is first attribute
      expect(subject[-1]).to eq(queue_name)  # queue_name is last attribute
    end

    it 'supports enumeration' do
      values = subject.to_a
      expect(values.first).to eq(body)
      expect(values.last).to eq(queue_name)
      expect(values.length).to eq(9)  # 9 attributes total
    end

    it 'supports hash conversion' do
      hash = subject.to_h
      expect(hash[:body]).to eq(body)
      expect(hash[:queue_name]).to eq(queue_name)
      expect(hash.keys).to contain_exactly(
        :body, :attributes, :md5_of_body, :md5_of_message_attributes,
        :message_attributes, :message_id, :receipt_handle, :delete, :queue_name
      )
    end
  end

  describe 'equality' do
    let(:message1) { described_class.new(body: body, queue_name: queue_name) }
    let(:message2) { described_class.new(body: body, queue_name: queue_name) }
    let(:message3) { described_class.new(body: 'different', queue_name: queue_name) }

    it 'compares messages by attribute values' do
      expect(message1).to eq(message2)
      expect(message1).not_to eq(message3)
    end
  end
end
