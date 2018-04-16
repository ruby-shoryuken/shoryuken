require 'spec_helper'

describe 'Shoryuken::Util' do
  subject do
    Class.new do
      extend Shoryuken::Util
    end
  end

  describe '#unparse_queues' do
    it 'returns queues and weights' do
      queues = %w[queue1 queue1 queue2 queue3 queue4 queue4 queue4]

      expect(subject.unparse_queues(queues)).to eq([['queue1', 2], ['queue2', 1], ['queue3', 1], ['queue4', 3]])
    end
  end

  describe '#worker_name' do
    let(:sqs_msg) do
      double Shoryuken::Message, message_id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', message_attributes: {}
    end

    it 'returns Shoryuken worker name' do
      expect(subject.worker_name(TestWorker, sqs_msg)).to eq 'TestWorker'
    end

    it 'returns ActiveJob worker name'
  end

  describe '#fire_event' do
    let(:value_holder) { Object.new }
    let(:callback_without_options) { proc { value_holder.value = :without_options } }
    let(:callback_with_options) { proc { |options| value_holder.value = [:with_options, options] } }

    after :all do
      Shoryuken.options[:lifecycle_events].delete(:some_event)
    end

    it 'triggers callbacks that do not accept arguments' do
      Shoryuken.options[:lifecycle_events][:some_event] = [callback_without_options]

      expect(value_holder).to receive(:value=).with(:without_options)
      subject.fire_event(:some_event)
    end

    it 'triggers callbacks that accept an argument' do
      Shoryuken.options[:lifecycle_events][:some_event] = [callback_with_options]

      expect(value_holder).to receive(:value=).with([:with_options, { my_option: :some_option }])
      subject.fire_event(:some_event, false, my_option: :some_option)
    end
  end
end
