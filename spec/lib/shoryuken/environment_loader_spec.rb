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
          <<-MSG.gsub(/^\s+/, '')
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
        allow_any_instance_of(Shoryuken::EnvironmentLoader).to receive(:config_file_options).and_return({ queues: config_queues })
        Shoryuken::EnvironmentLoader.setup_options(queues: cli_queues)
        expect(Shoryuken.options[:queues]).to eq(cli_queues)
      end
    end

    context 'when given queues through config only' do
      specify do
        allow_any_instance_of(Shoryuken::EnvironmentLoader).to receive(:config_file_options).and_return({ queues: config_queues })
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
