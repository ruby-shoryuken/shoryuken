require 'spec_helper'
require 'active_job'

RSpec.describe Shoryuken::EnvironmentLoader do
  subject { described_class.new({}) }

  describe '#parse_queues loads default queues' do
    before do
      allow(subject).to receive(:load_rails)
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
      allow(subject).to receive(:load_rails)
      allow(subject).to receive(:prefix_active_job_queue_names)
      allow(subject).to receive(:require_workers)
      allow(subject).to receive(:validate_queues)
      allow(subject).to receive(:validate_workers)
      allow(subject).to receive(:patch_deprecated_workers)
    end

    specify do
      Shoryuken.options[:queues] = ['queue1', 'queue2'] # default queues
      Shoryuken.options[:groups] = [[ 'custom', { queues: ['queue3'], delay: 25 }]]
      subject.load

      expect(Shoryuken.groups['default'][:queues]).to eq(%w[queue1 queue2])
      expect(Shoryuken.groups['default'][:delay]).to eq(Shoryuken.options[:delay])
      expect(Shoryuken.groups['custom'][:queues]).to eq(%w[queue3])
      expect(Shoryuken.groups['custom'][:delay]).to eq(25)
    end
  end


  describe '#prefix_active_job_queue_names' do
    before do
      allow(subject).to receive(:load_rails)
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

    it 'does not prefix url-based queues', pending: 'current behaviour' do
      Shoryuken.options[:queues] = ['https://example.com/test_queue1']
      Shoryuken.options[:groups] = {'group1' => {queues: ['https://example.com/test_group1_queue1']}}

      subject.load

      expect(Shoryuken.groups['default'][:queues]).to(eq(['https://example.com/test_queue1']))
      expect(Shoryuken.groups['group1'][:queues]).to(eq(['https://example.com/test_group1_queue1']))
    end

    it 'does not prefix arn-based queues', pending: 'current behaviour' do
      Shoryuken.options[:queues] = ['arn:aws:sqs:fake-region-1:1234:test_queue1']
      Shoryuken.options[:groups] = {'group1' => {queues: ['arn:aws:sqs:fake-region-1:1234:test_group1_queue1']}}

      subject.load

      expect(Shoryuken.groups['default'][:queues]).to(eq(['arn:aws:sqs:fake-region-1:1234:test_queue1']))
      expect(Shoryuken.groups['group1'][:queues]).to(eq(['arn:aws:sqs:fake-region-1:1234:test_group1_queue1']))
    end
  end
  describe "#setup_options" do
    let (:cli_queues) { { "queue1"=> 10, "queue2" => 20 } }
    let (:config_queues) { [["queue1", 8], ["queue2", 4]] }
    context "when given queues through config and CLI" do
      specify do
        allow_any_instance_of(Shoryuken::EnvironmentLoader).to receive(:config_file_options).and_return({ queues: config_queues })
        Shoryuken::EnvironmentLoader.setup_options(queues: cli_queues)
        expect(Shoryuken.options[:queues]).to eq(cli_queues)
      end
    end
    context "when given queues through config only" do
      specify do
        allow_any_instance_of(Shoryuken::EnvironmentLoader).to receive(:config_file_options).and_return({ queues: config_queues })
        Shoryuken::EnvironmentLoader.setup_options({})
        expect(Shoryuken.options[:queues]).to eq(config_queues)
      end
    end
    context "when given queues through CLI only" do
      specify do
        Shoryuken::EnvironmentLoader.setup_options(queues: cli_queues)
        expect(Shoryuken.options[:queues]).to eq(cli_queues)
      end
    end
  end
end
