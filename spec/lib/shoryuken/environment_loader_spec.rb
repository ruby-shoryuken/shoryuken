# frozen_string_literal: true

require 'active_job'

RSpec.describe Shoryuken::EnvironmentLoader do
  subject { described_class.new({}) }

  describe '#load' do
    before do
      Shoryuken.groups.clear
      # See issue: https://stackoverflow.com/a/63699568 for stubbing AWS errors
      allow(Shoryuken::Client)
        .to receive(:queues)
        .with('stubbed_queue')
        .and_raise(Aws::SQS::Errors::NonExistentQueue.new(nil, nil))
      allow(subject).to receive(:load_rails)
      allow(subject).to receive(:prefix_active_job_queue_names)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_workers)
      allow(subject).to receive(:patch_deprecated_workers)
      Shoryuken.options[:groups] = [['custom', { queues: ['stubbed_queue'] }]]
    end

    context 'when SQS reports a missing queue as QueueDoesNotExist' do
      before do
        allow(Shoryuken::Client)
          .to receive(:queues)
          .with('stubbed_queue')
          .and_raise(Aws::SQS::Errors::QueueDoesNotExist.new(nil, nil))
      end

      it 'raises QueueNotFoundError naming the queue' do
        expect { subject.load }.to raise_error(Shoryuken::Errors::QueueNotFoundError, /stubbed_queue do not exist/)
      end
    end

    context "when given queues don't exist" do
      specify do
        expect { subject.load }.to raise_error(
          Shoryuken::Errors::QueueNotFoundError,
          <<~MSG
            The specified queue(s) stubbed_queue do not exist.
            Try 'shoryuken sqs create QUEUE-NAME' for creating a queue with default settings.
            It's also possible that you don't have permission to access the specified queues.
          MSG
        )
      end
    end

    it 'validates the options before it parses the queues' do
      Shoryuken.options[:concurrency] = 0

      expect(subject).not_to receive(:parse_queues)
      expect { subject.load }.to raise_error(Shoryuken::Errors::InvalidConfigurationError, /concurrency/)
    end

    context 'when the polling strategy name is unknown' do
      before do
        Shoryuken.options[:polling_strategy] = 'NoSuchStrategy'
        Shoryuken.options[:queues] = ['stubbed_queue']
      end

      after { Shoryuken.options[:polling_strategy] = nil }

      it 'raises after it requires the workers' do
        expect { subject.load }.to raise_error(Shoryuken::Errors::InvalidPollingStrategyError, /polling_strategy/)
        expect(subject).to have_received(:require_workers)
      end
    end
  end

  describe '#check' do
    let(:contract) { instance_double(Shoryuken::Contracts::Options, validate!: nil) }

    before do
      Shoryuken.groups.clear
      Shoryuken.options[:groups] = nil
      allow(Shoryuken::Contracts::Options).to receive(:new).and_return(contract)
      allow(subject).to receive(:prefix_active_job_queue_names)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(Shoryuken).to receive(:active_job?).and_return(false)
      allow(Shoryuken.worker_registry).to receive(:queues).and_return(%w[queue1])
    end

    context 'when every queue has a worker' do
      before { Shoryuken.options[:queues] = ['queue1', ['queue1', 2]] }

      it 'returns no problems' do
        expect(subject.check).to eq([])
      end
    end

    context 'when an option has an invalid value' do
      before do
        Shoryuken.options[:queues] = %w[queue1]
        allow(contract).to receive(:validate!).and_raise(Shoryuken::Errors::InvalidConfigurationError, 'concurrency')
      end

      it 'raises before loading the workers' do
        expect { subject.check }.to raise_error(Shoryuken::Errors::InvalidConfigurationError)
        expect(subject).not_to have_received(:require_workers)
      end
    end

    context 'when a group names an unknown polling strategy' do
      before do
        Shoryuken.options[:queues] = %w[queue1]
        Shoryuken.options[:groups] = { custom: { polling_strategy: 'NoSuchStrategy', queues: %w[queue1] } }
      end

      it 'raises after loading the workers' do
        expect { subject.check }
          .to raise_error(Shoryuken::Errors::InvalidPollingStrategyError, /groups\.custom\.polling_strategy/)
        expect(subject).to have_received(:require_workers)
      end
    end

    context 'when a queue has no worker' do
      before { Shoryuken.options[:queues] = %w[queue1 queue2] }

      it 'reports the queue' do
        expect(subject.check).to eq(['No worker supplied for queue2'])
      end

      it 'does not also log it as a warning' do
        expect(Shoryuken.logger).not_to receive(:warn)

        subject.check
      end
    end

    context 'when a queue without a worker is listed more than once' do
      before { Shoryuken.options[:queues] = ['queue1', 'queue2', ['queue2', 2]] }

      it 'reports the queue once' do
        expect(subject.check).to eq(['No worker supplied for queue2'])
      end
    end

    context 'when a queue has no worker but ActiveJob is in use' do
      before do
        Shoryuken.options[:queues] = %w[queue1 queue2]
        allow(Shoryuken).to receive(:active_job?).and_return(true)
      end

      it 'returns no problems' do
        expect(subject.check).to eq([])
      end
    end

    context 'when no queues are configured' do
      before do
        Shoryuken.options[:queues] = []
        allow(subject).to receive(:validate_queues).and_call_original
      end

      it 'reports it' do
        expect(subject.check).to eq(['No queues supplied'])
      end

      it 'does not also log it as a warning' do
        expect(Shoryuken.logger).not_to receive(:warn)

        subject.check
      end
    end

    context 'when a queue does not exist' do
      before do
        Shoryuken.options[:queues] = %w[queue1]
        allow(subject).to receive(:validate_queues).and_call_original
        allow(Shoryuken::Client)
          .to receive(:queues)
          .with('queue1')
          .and_raise(Aws::SQS::Errors::NonExistentQueue.new(nil, nil))
      end

      it 'raises QueueNotFoundError' do
        expect { subject.check }.to raise_error(Shoryuken::Errors::QueueNotFoundError)
      end
    end
  end

  describe 'worker perform checks' do
    let(:contract) { instance_double(Shoryuken::Contracts::Options, validate!: nil) }
    let(:problems) { subject.check }

    before do
      Shoryuken.groups.clear
      Shoryuken.options[:groups] = nil
      Shoryuken.options[:queues] = %w[queue1]
      allow(Shoryuken::Contracts::Options).to receive(:new).and_return(contract)
      allow(subject).to receive(:prefix_active_job_queue_names)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(Shoryuken).to receive(:active_job?).and_return(false)
      allow(Shoryuken.worker_registry).to receive(:queues).and_return(%w[queue1])
      allow(Shoryuken.worker_registry).to receive(:workers).with('queue1').and_return([worker_class])
    end

    {
      '(sqs_msg, body)' => proc { |_sqs_msg, _body| },
      '(sqs_msg, body = nil)' => proc { |_sqs_msg, _body = nil| },
      '(*args)' => proc { |*_args| },
      '(sqs_msg, body, extra = nil)' => proc { |_sqs_msg, _body, _extra = nil| },
      '(sqs_msg, body, option: nil)' => proc { |_sqs_msg, _body, option: nil| }
    }.each do |signature, body|
      context "when perform takes #{signature}" do
        let(:worker_class) do
          Class.new do
            include Shoryuken::Worker

            define_method(:perform, &body)
          end
        end

        it 'reports no problem' do
          expect(problems).to eq([])
        end
      end
    end

    {
      '(name)' => [proc { |name| }, 'name'],
      '(sqs_msg, body, extra)' => [proc { |sqs_msg, body, extra| }, 'sqs_msg, body, extra'],
      '(sqs_msg, body, key:)' => [proc { |sqs_msg, body, key:| }, 'sqs_msg, body, key:']
    }.each do |signature, (body, formatted)|
      context "when perform takes #{signature}" do
        let(:worker_class) do
          Class.new do
            include Shoryuken::Worker

            define_method(:perform, &body)
          end
        end

        it 'reports the signature it takes' do
          expect(problems).to eq(
            ["#{worker_class.inspect}#perform must accept (sqs_msg, body); it takes (#{formatted})"]
          )
        end
      end
    end

    context 'when perform takes every kind of parameter' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(sqs_msg, body = nil, *rest, key:, option: nil, **opts, &block); end
        end
      end

      it 'formats each kind' do
        expect(problems).to eq(
          [
            "#{worker_class.inspect}#perform must accept (sqs_msg, body); it takes " \
            '(sqs_msg, body = ..., *rest, key:, option: ..., **opts, &block)'
          ]
        )
      end
    end

    shared_examples 'it formats the parameters as written' do |formatted|
      it "reports it takes (#{formatted})" do
        expect(problems).to eq(
          ["#{worker_class.inspect}#perform must accept (sqs_msg, body); it takes (#{formatted})"]
        )
      end
    end

    context 'when perform takes (sqs_msg, body, *, key:)' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(sqs_msg, body, *, key:); end
        end
      end

      it_behaves_like 'it formats the parameters as written', 'sqs_msg, body, *, key:'
    end

    context 'when perform takes (sqs_msg, body, extra, **)' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(sqs_msg, body, extra, **); end
        end
      end

      it_behaves_like 'it formats the parameters as written', 'sqs_msg, body, extra, **'
    end

    context 'when perform takes (sqs_msg, body, extra, &)' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(sqs_msg, body, extra, &); end
        end
      end

      it_behaves_like 'it formats the parameters as written', 'sqs_msg, body, extra, &'
    end

    context 'when perform takes (sqs_msg, body, extra, ...)' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(sqs_msg, body, extra, ...); end
        end
      end

      it_behaves_like 'it formats the parameters as written', 'sqs_msg, body, extra, ...'
    end

    context 'when perform takes (sqs_msg, **nil)' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(sqs_msg, **nil); end
        end
      end

      it_behaves_like 'it formats the parameters as written', 'sqs_msg, **nil'
    end

    context 'when perform is protected' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          protected

          def perform(_sqs_msg, _body); end
        end
      end

      it 'reports it missing' do
        expect(problems).to eq(["#{worker_class.inspect} must define perform(sqs_msg, body)"])
      end
    end

    context 'when the worker has no perform' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def preform(_sqs_msg, _body); end
        end
      end

      it 'reports it missing' do
        expect(problems).to eq(["#{worker_class.inspect} must define perform(sqs_msg, body)"])
      end
    end

    context 'when perform is private' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          private

          def perform(_sqs_msg, _body); end
        end
      end

      it 'reports it missing' do
        expect(problems).to eq(["#{worker_class.inspect} must define perform(sqs_msg, body)"])
      end
    end

    context 'when a batch worker has the wrong perform' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          shoryuken_options queue: 'batch_perform_check', batch: true

          def perform(_sqs_msgs); end
        end
      end

      it 'names the batch signature' do
        expect(problems).to eq(
          ["#{worker_class.inspect}#perform must accept (sqs_msgs, bodies); it takes (_sqs_msgs)"]
        )
      end
    end

    context 'when the worker is the ActiveJob wrapper' do
      let(:worker_class) { Shoryuken::ActiveJob::JobWrapper }

      it 'reports no problem' do
        expect(problems).to eq([])
      end
    end

    context 'when the worker is registered for several configured queues' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(_name); end
        end
      end

      before do
        Shoryuken.options[:queues] = %w[queue1 queue2]
        allow(Shoryuken.worker_registry).to receive(:queues).and_return(%w[queue1 queue2])
        allow(Shoryuken.worker_registry).to receive(:workers).with('queue2').and_return([worker_class])
      end

      it 'reports it once' do
        expect(problems.size).to eq(1)
      end
    end

    context 'when a queue has a wrong worker registered before a valid one' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(_name); end
        end
      end
      let(:valid_worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(_sqs_msg, _body); end
        end
      end
      let(:registry) { Shoryuken::DefaultWorkerRegistry.new }

      before do
        registry.register_worker('queue1', worker_class)
        registry.register_worker('queue1', valid_worker_class)
        allow(Shoryuken).to receive(:worker_registry).and_return(registry)
      end

      it 'reports the wrong one' do
        expect(problems).to eq(
          ["#{worker_class.inspect}#perform must accept (sqs_msg, body); it takes (_name)"]
        )
      end
    end

    context 'when a queue has an abstract base worker and its subclass' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker
        end
      end
      let(:subclass) do
        Class.new(worker_class) do
          def perform(_sqs_msg, _body); end
        end
      end
      let(:registry) { Shoryuken::DefaultWorkerRegistry.new }

      before do
        registry.register_worker('queue1', worker_class)
        registry.register_worker('queue1', subclass)
        allow(Shoryuken).to receive(:worker_registry).and_return(registry)
      end

      it 'reports no problem' do
        expect(problems).to eq([])
      end

      context 'when the base worker is the fallback worker' do
        before { registry.register_worker('queue1', worker_class) }

        it 'reports it missing' do
          expect(problems).to eq(["#{worker_class.inspect} must define perform(sqs_msg, body)"])
        end
      end
    end

    context 'when a queue has an abstract base worker whose subclass uses another queue' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker
        end
      end
      let(:subclass) do
        Class.new(worker_class) do
          def perform(_sqs_msg, _body); end
        end
      end
      let(:valid_worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(_sqs_msg, _body); end
        end
      end
      let(:registry) { Shoryuken::DefaultWorkerRegistry.new }

      before do
        Shoryuken.options[:queues] = %w[queue1 queue2]
        registry.register_worker('queue1', worker_class)
        registry.register_worker('queue2', subclass)
        registry.register_worker('queue1', valid_worker_class)
        allow(Shoryuken).to receive(:worker_registry).and_return(registry)
      end

      it 'reports no problem' do
        expect(problems).to eq([])
      end
    end

    context 'when a queue has a worker without perform and without a subclass before a valid one' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def preform(_sqs_msg, _body); end
        end
      end
      let(:valid_worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(_sqs_msg, _body); end
        end
      end
      let(:registry) { Shoryuken::DefaultWorkerRegistry.new }

      before do
        registry.register_worker('queue1', worker_class)
        registry.register_worker('queue1', valid_worker_class)
        allow(Shoryuken).to receive(:worker_registry).and_return(registry)
      end

      it 'reports it missing' do
        expect(problems).to eq(["#{worker_class.inspect} must define perform(sqs_msg, body)"])
      end
    end

    context 'when a queue has a base worker with a wrong perform and its subclass' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(_name); end
        end
      end
      let(:subclass) do
        Class.new(worker_class) do
          def perform(_sqs_msg, _body); end
        end
      end
      let(:registry) { Shoryuken::DefaultWorkerRegistry.new }

      before do
        registry.register_worker('queue1', worker_class)
        registry.register_worker('queue1', subclass)
        allow(Shoryuken).to receive(:worker_registry).and_return(registry)
      end

      it 'reports the base worker' do
        expect(problems).to eq(
          ["#{worker_class.inspect}#perform must accept (sqs_msg, body); it takes (_name)"]
        )
      end
    end

    context 'when loading for start' do
      let(:worker_class) do
        Class.new do
          include Shoryuken::Worker

          def perform(_name); end
        end
      end

      before do
        allow(subject).to receive(:validate_workers).and_call_original
      end

      it 'logs the problem as a warning and does not raise' do
        expect(Shoryuken.logger).to receive(:warn) do |&block|
          expect(block.call).to eq(
            "#{worker_class.inspect}#perform must accept (sqs_msg, body); it takes (_name)"
          )
        end

        subject.load
      end
    end
  end

  describe '#parse_queues loads default queues' do
    before do
      allow(subject).to receive(:initialize_rails)
      allow(subject).to receive(:prefix_active_job_queue_names)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(subject).to receive(:validate_workers)
      allow(subject).to receive(:patch_deprecated_workers)
    end

    specify do
      Shoryuken.options[:queues] = ['queue1', ['queue2', 2]]
      subject.load

      expect(Shoryuken.groups['default'][:queues]).to eq(%w[queue1 queue2 queue2])
    end
  end

  describe '#parse_queues includes delay per groups' do
    before do
      allow(subject).to receive(:initialize_rails)
      allow(subject).to receive(:prefix_active_job_queue_names)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(subject).to receive(:validate_workers)
      allow(subject).to receive(:patch_deprecated_workers)
    end

    specify do
      Shoryuken.options[:queues] = %w[queue1 queue2] # default queues
      Shoryuken.options[:groups] = [['custom', { queues: ['queue3'], delay: 25 }]]
      subject.load

      expect(Shoryuken.groups['default'][:queues]).to eq(%w[queue1 queue2])
      expect(Shoryuken.groups['default'][:delay]).to eq(Shoryuken.options[:delay])
      expect(Shoryuken.groups['custom'][:queues]).to eq(%w[queue3])
      expect(Shoryuken.groups['custom'][:delay]).to eq(25)
    end
  end

  describe '#prefix_active_job_queue_names' do
    before do
      allow(subject).to receive(:initialize_rails)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(subject).to receive(:validate_workers)
      allow(subject).to receive(:patch_deprecated_workers)

      ActiveJob::Base.queue_name_prefix    = 'test'
      ActiveJob::Base.queue_name_delimiter = '_'

      allow(Shoryuken).to receive(:active_job?).and_return(true)

      Shoryuken.active_job_queue_name_prefixing = true
    end

    specify do
      Shoryuken.options[:queues] = ['queue1', ['queue2', 2]]

      Shoryuken.options[:groups] = {
        'group1' => { queues: %w[group1_queue1 group1_queue2] }
      }

      subject.load

      expect(Shoryuken.groups['default'][:queues]).to eq(%w[test_queue1 test_queue2 test_queue2])
      expect(Shoryuken.groups['group1'][:queues]).to eq(%w[test_group1_queue1 test_group1_queue2])
    end

    it 'does not prefix url-based queues' do
      Shoryuken.options[:queues] = ['https://example.com/test_queue1']
      Shoryuken.options[:groups] = { 'group1' => { queues: ['https://example.com/test_group1_queue1'] } }

      subject.load

      expect(Shoryuken.groups['default'][:queues]).to(eq(['https://example.com/test_queue1']))
      expect(Shoryuken.groups['group1'][:queues]).to(eq(['https://example.com/test_group1_queue1']))
    end

    it 'does not prefix http url-based queues' do
      Shoryuken.options[:queues] = ['http://localhost:9324/000000000000/test_queue1']
      Shoryuken.options[:groups] = { 'group1' => { queues: ['http://localhost:9324/000000000000/test_group1_queue1'] } }

      subject.load

      expect(Shoryuken.groups['default'][:queues]).to(eq(['http://localhost:9324/000000000000/test_queue1']))
      expect(Shoryuken.groups['group1'][:queues]).to(eq(['http://localhost:9324/000000000000/test_group1_queue1']))
    end

    it 'does not prefix url-based queues with an upper-case scheme' do
      Shoryuken.options[:queues] = ['HTTP://localhost:9324/000000000000/test_queue1']

      subject.load

      expect(Shoryuken.groups['default'][:queues]).to(eq(['HTTP://localhost:9324/000000000000/test_queue1']))
    end

    it 'does not prefix arn-based queues' do
      Shoryuken.options[:queues] = ['arn:aws:sqs:fake-region-1:1234:test_queue1']
      Shoryuken.options[:groups] = { 'group1' => { queues: ['arn:aws:sqs:fake-region-1:1234:test_group1_queue1'] } }

      subject.load

      expect(Shoryuken.groups['default'][:queues]).to(eq(['arn:aws:sqs:fake-region-1:1234:test_queue1']))
      expect(Shoryuken.groups['group1'][:queues]).to(eq(['arn:aws:sqs:fake-region-1:1234:test_group1_queue1']))
    end
  end

  describe '#setup_options' do
    let(:cli_queues) { { 'queue1' => 10, 'queue2' => 20 } }
    let(:config_queues) { [['queue1', 8], ['queue2', 4]] }

    context 'when given queues through config and CLI' do
      specify do
        allow_any_instance_of(Shoryuken::EnvironmentLoader)
          .to receive(:config_file_options).and_return({ queues: config_queues })
        Shoryuken::EnvironmentLoader.setup_options(queues: cli_queues)
        expect(Shoryuken.options[:queues]).to eq(cli_queues)
      end
    end

    context 'when given queues through config only' do
      specify do
        allow_any_instance_of(Shoryuken::EnvironmentLoader)
          .to receive(:config_file_options).and_return({ queues: config_queues })
        Shoryuken::EnvironmentLoader.setup_options({})
        expect(Shoryuken.options[:queues]).to eq(config_queues)
      end
    end

    context 'when given queues through CLI only' do
      specify do
        Shoryuken::EnvironmentLoader.setup_options(queues: cli_queues)
        expect(Shoryuken.options[:queues]).to eq(cli_queues)
      end
    end
  end
end
