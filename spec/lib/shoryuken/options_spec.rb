# frozen_string_literal: true

RSpec.describe Shoryuken::Options do
  subject { Shoryuken.shoryuken_options }

  describe '.on_stop' do
    specify do
      on_stop = proc {}
      Shoryuken.on_stop(&on_stop)

      expect(Shoryuken.stop_callback).to eq(on_stop)
    end
  end

  describe '.on_start' do
    specify do
      on_start = proc {}
      Shoryuken.on_start(&on_start)

      expect(Shoryuken.start_callback).to eq(on_start)
    end
  end

  describe '#on' do
    let(:options) { described_class.new }

    it 'does not leak handlers or queues into the defaults' do
      options.on(:startup) {}
      options.options[:queues] << 'default'

      expect(described_class.new.options[:lifecycle_events]).to all(satisfy { |_event, handlers| handlers.empty? })
      expect(described_class.new.options[:queues]).to be_empty
      expect(described_class::DEFAULTS[:lifecycle_events][:startup]).to be_empty
    end
  end

  describe '.add_group adds queues and optional delay' do
    before do
      Shoryuken.groups.clear
      Shoryuken.add_group('group1', 25)
      Shoryuken.add_group('group2', 25)
      Shoryuken.add_group('group3', 25, delay: 5)
    end

    specify do
      subject.add_queue('queue1', 1, 'group1')
      subject.add_queue('queue2', 2, 'group2')
      subject.add_queue('queue3', 1, 'group3')

      expect(subject.groups['group1'][:queues]).to eq(%w[queue1])
      expect(subject.groups['group2'][:queues]).to eq(%w[queue2 queue2])
      expect(subject.groups['group3'][:queues]).to eq(%w[queue3])
      expect(subject.groups['group3'][:delay]).to eq(5)
    end
  end

  describe '.add_group with polling_strategy' do
    before do
      Shoryuken.groups.clear
    end

    it 'stores the polling_strategy in the group configuration' do
      Shoryuken.add_group('group1', 25, polling_strategy: Shoryuken::Polling::StrictPriority)

      expect(Shoryuken.groups['group1'][:polling_strategy]).to eq(Shoryuken::Polling::StrictPriority)
    end

    it 'defaults polling_strategy to nil when not provided' do
      Shoryuken.add_group('group1', 25)

      expect(Shoryuken.groups['group1'][:polling_strategy]).to be_nil
    end

    it 'accepts a string polling_strategy' do
      Shoryuken.add_group('group1', 25, polling_strategy: 'StrictPriority')

      expect(Shoryuken.groups['group1'][:polling_strategy]).to eq('StrictPriority')
    end

    it 'raises InvalidPollingStrategyError for invalid polling_strategy type' do
      expect {
        Shoryuken.add_group('group1', 25, polling_strategy: 123)
      }.to raise_error(Shoryuken::Errors::InvalidPollingStrategyError)
    end
  end

  describe '.delay works for each group' do
    specify do
      Shoryuken.add_group('group1', 25)
      Shoryuken.add_group('group2', 25, delay: 5)
      subject.add_queue('queue1', 1, 'group1')
      subject.add_queue('queue2', 2, 'group2')

      expect(subject.delay('group1')).to eq(Shoryuken.options[:delay])
      expect(subject.delay('group2')).to eq(5.0)
    end
  end

  describe '.ungrouped_queues' do
    before do
      Shoryuken.groups.clear
      Shoryuken.add_group('group1', 25)
      Shoryuken.add_group('group2', 25)
    end

    specify do
      subject.add_queue('queue1', 1, 'group1')
      subject.add_queue('queue2', 2, 'group2')

      expect(subject.ungrouped_queues).to eq(%w[queue1 queue2 queue2])
    end
  end

  describe '.sqs_client_receive_message_opts' do
    before do
      Shoryuken.sqs_client_receive_message_opts
    end

    specify do
      Shoryuken.sqs_client_receive_message_opts = { test: 1 }
      expect(Shoryuken.sqs_client_receive_message_opts).to eq('default' => { test: 1 })

      Shoryuken.sqs_client_receive_message_opts['group1'] = { test: 2 }

      expect(Shoryuken.sqs_client_receive_message_opts).to eq(
        'default' => { test: 1 },
        'group1' => { test: 2 }
      )
    end
  end

  describe '.receive_message_opts_for' do
    before do
      Shoryuken.sqs_client_receive_message_opts['group1'] = { wait_time_seconds: 20 }
      Shoryuken.sqs_client_receive_message_opts['queue1'] = { visibility_timeout: 10 }
    end

    it 'returns the options of the queue over those of its group' do
      expect(Shoryuken.receive_message_opts_for('queue1', 'group1')).to eq(visibility_timeout: 10)
    end

    it 'returns the options of the group when the queue has none' do
      expect(Shoryuken.receive_message_opts_for('queue2', 'group1')).to eq(wait_time_seconds: 20)
    end

    it 'returns an empty Hash when neither has options' do
      expect(Shoryuken.receive_message_opts_for('queue2', nil)).to eq({})
    end

    it 'returns a copy, so a change does not leak into the stored options' do
      Shoryuken.receive_message_opts_for('queue1', 'group1')[:max_number_of_messages] = 1

      expect(Shoryuken.sqs_client_receive_message_opts['queue1']).to eq(visibility_timeout: 10)
    end
  end

  describe '.register_worker' do
    it 'registers a worker' do
      subject.worker_registry.clear
      subject.register_worker('default', TestWorker)
      expect(subject.worker_registry.workers('default')).to eq([TestWorker])
    end

    it 'registers a batchable worker' do
      subject.worker_registry.clear
      TestWorker.get_shoryuken_options['batch'] = true
      subject.register_worker('default', TestWorker)
      expect(subject.worker_registry.workers('default')).to eq([TestWorker])
    end

    it 'allows multiple workers' do
      subject.worker_registry.clear
      subject.register_worker('default', TestWorker)
      expect(subject.worker_registry.workers('default')).to eq([TestWorker])

      class Test2Worker
        include Shoryuken::Worker

        shoryuken_options queue: 'default'

        def perform(sqs_msg, body); end
      end

      expect(subject.worker_registry.workers('default')).to eq([Test2Worker])
    end

    it 'raises an exception when mixing batchable with non batchable' do
      subject.worker_registry.clear
      TestWorker.get_shoryuken_options['batch'] = true
      subject.register_worker('default', TestWorker)

      expect {
        class BatchableWorker
          include Shoryuken::Worker

          shoryuken_options queue: 'default', batch: true

          def perform(sqs_msg, body); end
        end
      }.to raise_error(
        'Could not register BatchableWorker for default, because TestWorker is already registered for this queue, ' \
        "and Shoryuken doesn't support a batchable worker for a queue with multiple workers"
      )
    end
  end

  describe '.polling_strategy' do
    context 'when not set' do
      specify do
        expect(Shoryuken.polling_strategy('default')).to eq Shoryuken::Polling::WeightedRoundRobin
        expect(Shoryuken.polling_strategy('group1')).to eq Shoryuken::Polling::WeightedRoundRobin
      end
    end

    context 'when set to StrictPriority string' do
      before do
        Shoryuken.options[:polling_strategy] = 'StrictPriority'

        Shoryuken.options[:groups] = {
          'group1' => {
            polling_strategy: 'StrictPriority'
          }
        }
      end

      specify do
        expect(Shoryuken.polling_strategy('default')).to eq Shoryuken::Polling::StrictPriority
        expect(Shoryuken.polling_strategy('group1')).to eq Shoryuken::Polling::StrictPriority
      end
    end

    context 'when set to WeightedRoundRobin string' do
      before do
        Shoryuken.options[:polling_strategy] = 'WeightedRoundRobin'

        Shoryuken.options[:groups] = {
          'group1' => {
            polling_strategy: 'WeightedRoundRobin'
          }
        }
      end

      specify do
        expect(Shoryuken.polling_strategy('default')).to eq Shoryuken::Polling::WeightedRoundRobin
        expect(Shoryuken.polling_strategy('group1')).to eq Shoryuken::Polling::WeightedRoundRobin
      end
    end

    context 'when set to non-existent string' do
      before do
        Shoryuken.options[:polling_strategy] = 'NonExistent1'

        Shoryuken.options[:groups] = {
          'group1' => {
            polling_strategy: 'NonExistent2'
          }
        }
      end

      specify do
        expect { Shoryuken.polling_strategy('default') }.to raise_error(Shoryuken::Errors::InvalidPollingStrategyError)
        expect { Shoryuken.polling_strategy('group1') }.to raise_error(Shoryuken::Errors::InvalidPollingStrategyError)
      end
    end

    context 'when set to a class' do
      before do
        class Foo < Shoryuken::Polling::BaseStrategy; end
        class Bar < Shoryuken::Polling::BaseStrategy; end

        Shoryuken.options[:polling_strategy] = Foo

        Shoryuken.options[:groups] = {
          'group1' => {
            polling_strategy: Bar
          }
        }
      end

      specify do
        expect(Shoryuken.polling_strategy('default')).to eq Foo
        expect(Shoryuken.polling_strategy('group1')).to eq Bar
      end
    end

    context 'when set via add_group' do
      before do
        class Baz < Shoryuken::Polling::BaseStrategy; end

        Shoryuken.groups.clear
        Shoryuken.add_group('custom_group', 25, polling_strategy: Baz)
      end

      specify do
        expect(Shoryuken.polling_strategy('custom_group')).to eq Baz
      end
    end
  end
end
