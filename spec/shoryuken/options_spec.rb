require 'spec_helper'

RSpec.describe Shoryuken::Options do
  describe '.add_group' do
    before do
      Shoryuken.groups.clear
      Shoryuken.add_group('group1', 25)
      Shoryuken.add_group('group2', 25)
    end

    specify do
      described_class.add_queue('queue1', 1, 'group1')
      described_class.add_queue('queue2', 2, 'group2')

      expect(described_class.groups['group1'][:queues]).to eq(%w(queue1))
      expect(described_class.groups['group2'][:queues]).to eq(%w(queue2 queue2))
    end
  end

  describe '.sqs_client_receive_message_opts' do
    before do
      Shoryuken.sqs_client_receive_message_opts
    end

    specify do
      Shoryuken.sqs_client_receive_message_opts = { test: 1 }
      expect(Shoryuken.sqs_client_receive_message_opts).to eq('default' => { test: 1 })

      Shoryuken.sqs_client_receive_message_opts['my_group'] = { test: 2 }
      expect(Shoryuken.sqs_client_receive_message_opts).to eq('default' => { test: 1 }, 'my_group' => { test: 2 })
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
      }.to raise_error("Could not register BatchableWorker for default, because TestWorker is already registered for this queue, " \
        "and Shoryuken doesn't support a batchable worker for a queue with multiple workers")
    end
  end
end
