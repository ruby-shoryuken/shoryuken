# frozen_string_literal: true

RSpec.describe Shoryuken::OptionsContract do
  let(:options) { Shoryuken::Options::DEFAULTS.merge(queues: ['default']) }

  def validate(opts = options)
    described_class.validate!(opts)
  end

  def expect_invalid(key, opts)
    expect { validate(opts) }.to raise_error(Shoryuken::Errors::InvalidConfigurationError, /Invalid value for #{key}:/)
  end

  context 'with valid options' do
    it 'accepts the defaults' do
      expect(Shoryuken.logger).not_to receive(:warn)

      expect { validate(Shoryuken::Options::DEFAULTS) }.not_to raise_error
    end

    it 'accepts every documented config file and CLI option' do
      expect(Shoryuken.logger).not_to receive(:warn)

      opts = options.merge(
        concurrency: 10,
        delay: 2.5,
        timeout: nil,
        polling_strategy: 'StrictPriority',
        queues: ['queue1', ['queue2', 2], %w[queue3 3], ['https://sqs.us-east-1.amazonaws.com/1/queue4'],
                 'arn:aws:sqs:us-east-1:1:queue5'],
        groups: {
          group1: { concurrency: 2, delay: 0, polling_strategy: Shoryuken::Polling::StrictPriority, queues: ['q1'] },
          group2: { queues: [['q2', 1]] }
        },
        aws: { region: 'us-east-1' },
        config_file: Pathname.new('config/shoryuken.yml'),
        require: './workers',
        logfile: 'log/shoryuken.log',
        pidfile: 'tmp/shoryuken.pid',
        daemon: false,
        rails: true,
        verbose: nil
      )

      expect { validate(opts) }.not_to raise_error
    end

    it 'accepts groups given as an array of pairs' do
      expect { validate(options.merge(groups: [['custom', { queues: ['q1'], delay: 25 }]])) }.not_to raise_error
    end
  end

  context 'with an unknown key' do
    it 'warns with the key name and does not raise' do
      expect(Shoryuken.logger).to receive(:warn) do |&block|
        expect(block.call).to eq("Unknown option 'concurency' is ignored; check it for a typo")
      end

      expect { validate(options.merge(concurency: 10)) }.not_to raise_error
    end

    it 'warns with the group and key name for an unknown group key' do
      expect(Shoryuken.logger).to receive(:warn) do |&block|
        expect(block.call).to eq("Unknown option 'groups.custom.dealy' is ignored; check it for a typo")
      end

      validate(options.merge(groups: { custom: { queues: ['q1'], dealy: 5 } }))
    end
  end

  context 'with a wrong type' do
    it { expect_invalid('concurrency', options.merge(concurrency: '25')) }
    it { expect_invalid('delay', options.merge(delay: 'soon')) }
    it { expect_invalid('timeout', options.merge(timeout: '8')) }
    it { expect_invalid('aws', options.merge(aws: 'us-east-1')) }
    it { expect_invalid('queues', options.merge(queues: 'default')) }
    it { expect_invalid('queues', options.merge(queues: [['default', 'high']])) }
    it { expect_invalid('queues', options.merge(queues: [['default', 1, 2]])) }
    it { expect_invalid('queues', options.merge(queues: [''])) }
    it { expect_invalid('polling_strategy', options.merge(polling_strategy: 1)) }
    it { expect_invalid('daemon', options.merge(daemon: 'yes')) }
    it { expect_invalid('logfile', options.merge(logfile: 1)) }
    it { expect_invalid('thread_priority', options.merge(thread_priority: nil)) }
    it { expect_invalid('groups', options.merge(groups: 'custom')) }

    it 'names the group of an invalid group option' do
      expect_invalid('groups.custom.queues', options.merge(groups: { custom: { queues: 'q1' } }))
    end

    it 'rejects a group that is not a Hash' do
      expect { validate(options.merge(groups: { custom: ['q1'] })) }
        .to raise_error(Shoryuken::Errors::InvalidConfigurationError, 'Invalid groups.custom: must be a Hash')
    end
  end

  context 'with an out-of-range value' do
    it { expect_invalid('concurrency', options.merge(concurrency: 0)) }
    it { expect_invalid('concurrency', options.merge(concurrency: nil)) }
    it { expect_invalid('delay', options.merge(delay: -1)) }
    it { expect_invalid('timeout', options.merge(timeout: -1)) }
    it { expect_invalid('groups.custom.concurrency', options.merge(groups: { custom: { concurrency: 0 } })) }
  end

  describe 'Shoryuken::EnvironmentLoader#load' do
    subject(:loader) { Shoryuken::EnvironmentLoader.new({}) }

    it 'validates the options before it parses the queues' do
      Shoryuken.options[:concurrency] = 0

      expect(loader).not_to receive(:parse_queues)
      expect { loader.load }.to raise_error(Shoryuken::Errors::InvalidConfigurationError, /concurrency/)
    end
  end
end
