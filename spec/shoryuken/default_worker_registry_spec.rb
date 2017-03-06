require 'spec_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe Shoryuken::DefaultWorkerRegistry do
  class RegistryTestWorker
    include Shoryuken::Worker

    shoryuken_options queue: 'registry-test'

    def perform(sqs_msg, body); end
  end

  subject do
    Shoryuken.worker_registry
  end

  before do
    subject.register_worker 'registry-test', RegistryTestWorker
  end

  describe 'a registry containing workers is cleared' do
    it 'removes all registrations' do
      queue = 'some-other-queue'

      registry = described_class.new

      worker_class = Class.new do
        include Shoryuken::Worker

        shoryuken_options queue: queue

        def perform(sqs_msg, body); end
      end

      registry.register_worker(queue, worker_class)

      expect(registry.workers(queue)).to eq([worker_class])

      registry.clear

      expect(registry.workers(queue)).to eq([])
    end
  end

  describe 'a registry with workers is handling messages' do
    def build_message(queue, explicit_worker = nil)
      attributes = {}

      if explicit_worker
        attributes['shoryuken_class'] = { string_value: explicit_worker.to_s, data_type: 'String' }
      end

      double(Shoryuken::Message,
             body: 'test',
             message_attributes: attributes,
             message_id: SecureRandom.uuid)
    end

    context 'a batch of messages is being processed' do
      it 'returns an instance of the worker registered for that queue' do
        batch = [build_message('default', RegistryTestWorker)]
        expect(subject.fetch_worker('default', batch)).to be_instance_of(TestWorker)
      end
    end

    context 'a single message is being processed' do
      context 'a worker class name is included in the message attributes' do
        it 'returns an instance of that worker' do
          message = build_message('default', RegistryTestWorker)
          expect(subject.fetch_worker('default', message)).to be_instance_of(RegistryTestWorker)
        end
      end

      context 'a worker class name is not included in the message attributes' do
        it 'returns an instance of the worker registered for that queue' do
          message = build_message('default')
          expect(subject.fetch_worker('default', message)).to be_instance_of(TestWorker)

          message = build_message('registry-test')
          expect(subject.fetch_worker('registry-test', message)).to be_instance_of(RegistryTestWorker)
        end
      end
    end
  end
end
