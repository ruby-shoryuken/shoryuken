# frozen_string_literal: true

RSpec.describe Shoryuken::Worker::InlineExecutor do
  before do
    Shoryuken.worker_executor = described_class
  end

  describe '.perform_async' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform).with(anything, 'test')

      TestWorker.perform_async('test')
    end

    it 'properly sets message_attributes' do
      custom_attributes = {
        'custom_key' => { string_value: 'custom_value', data_type: 'String' }
      }

      expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msg, _|
        expect(sqs_msg.message_attributes).to include('shoryuken_class')
        expect(sqs_msg.message_attributes).to include('custom_key')
        expect(sqs_msg.message_attributes['custom_key'][:string_value]).to eq('custom_value')
      end

      TestWorker.perform_async('test', message_attributes: custom_attributes)
    end
  end

  describe '.perform_in' do
    specify do
      expect_any_instance_of(TestWorker).to receive(:perform).with(anything, 'test')

      TestWorker.perform_in(60, 'test')
    end

    it 'properly passes message_attributes to perform_async' do
      custom_attributes = {
        'custom_key' => { string_value: 'custom_value', data_type: 'String' }
      }

      expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msg, _|
        expect(sqs_msg.message_attributes).to include('shoryuken_class')
        expect(sqs_msg.message_attributes).to include('custom_key')
        expect(sqs_msg.message_attributes['custom_key'][:string_value]).to eq('custom_value')
      end

      TestWorker.perform_in(60, 'test', message_attributes: custom_attributes)
    end
  end

  context 'batch' do
    before do
      TestWorker.get_shoryuken_options['batch'] = true
    end

    after do
      TestWorker.get_shoryuken_options['batch'] = false
    end

    describe '.perform_async' do
      specify do
        expect_any_instance_of(TestWorker).to receive(:perform).with(anything, ['test'])

        TestWorker.perform_async('test')
      end

      it 'properly passes message_attributes with batch' do
        custom_attributes = {
          'custom_key' => { string_value: 'custom_value', data_type: 'String' }
        }

        expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msgs, _|
          expect(sqs_msgs.first.message_attributes).to include('shoryuken_class')
          expect(sqs_msgs.first.message_attributes).to include('custom_key')
          expect(sqs_msgs.first.message_attributes['custom_key'][:string_value]).to eq('custom_value')
        end

        TestWorker.perform_async('test', message_attributes: custom_attributes)
      end
    end

    describe '.perform_in' do
      specify do
        expect_any_instance_of(TestWorker).to receive(:perform).with(anything, ['test'])

        TestWorker.perform_in(60, 'test')
      end

      it 'properly passes message_attributes with batch' do
        custom_attributes = {
          'custom_key' => { string_value: 'custom_value', data_type: 'String' }
        }

        expect_any_instance_of(TestWorker).to receive(:perform) do |_, sqs_msgs, _|
          expect(sqs_msgs.first.message_attributes).to include('shoryuken_class')
          expect(sqs_msgs.first.message_attributes).to include('custom_key')
          expect(sqs_msgs.first.message_attributes['custom_key'][:string_value]).to eq('custom_value')
        end

        TestWorker.perform_in(60, 'test', message_attributes: custom_attributes)
      end
    end
  end
end
