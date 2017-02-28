require 'spec_helper'

RSpec.describe Shoryuken do
  describe '.add_queue' do
    after { Shoryuken.queues.clear }

    it 'adds queues' do
      described_class.add_queue('default')
      expect(described_class.queues).to eq(['default'])

      described_class.add_queue('high', 2)
      expect(described_class.queues).to eq(%w(default high high))
    end
  end

  describe '.register_worker' do
    it 'registers a worker' do
      described_class.worker_registry.clear
      described_class.register_worker('default', TestWorker)
      expect(described_class.worker_registry.workers('default')).to eq([TestWorker])
    end

    it 'registers a batchable worker' do
      described_class.worker_registry.clear
      TestWorker.get_shoryuken_options['batch'] = true
      described_class.register_worker('default', TestWorker)
      expect(described_class.worker_registry.workers('default')).to eq([TestWorker])
    end

    it 'allows multiple workers' do
      described_class.worker_registry.clear
      described_class.register_worker('default', TestWorker)
      expect(described_class.worker_registry.workers('default')).to eq([TestWorker])

      class Test2Worker
        include Shoryuken::Worker

        shoryuken_options queue: 'default'

        def perform(sqs_msg, body); end
      end

      expect(described_class.worker_registry.workers('default')).to eq([Test2Worker])
    end

    it 'raises an exception when mixing batchable with non batchable' do
      described_class.worker_registry.clear
      TestWorker.get_shoryuken_options['batch'] = true
      described_class.register_worker('default', TestWorker)

      expect {
        class BatchableWorker
          include Shoryuken::Worker

          shoryuken_options queue: 'default', batch: true

          def perform(sqs_msg, body); end
        end
      }.to raise_error("Could not register BatchableWorker for 'default', because TestWorker is already registered for this queue, " \
                       "and Shoryuken doesn't support a batchable worker for a queue with multiple workers")
    end
  end
end
