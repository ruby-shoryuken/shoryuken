# frozen_string_literal: true

RSpec.describe Shoryuken::Contracts::PollingStrategies do
  def errors(opts)
    described_class.new.call(opts).errors
  end

  it 'accepts no strategy, a Class, the built-in names and the name of a defined constant' do
    opts = {
      polling_strategy: 'StrictPriority',
      groups: {
        group1: { polling_strategy: 'WeightedRoundRobin' },
        group2: { polling_strategy: 'Shoryuken::Polling::StrictPriority' },
        group3: { polling_strategy: Shoryuken::Polling::StrictPriority },
        group4: { queues: ['q1'] }
      }
    }

    expect(errors(opts)).to be_empty
    expect(errors({})).to be_empty
  end

  it 'rejects an unknown global name when there are top-level queues' do
    expect(errors({ polling_strategy: 'NoSuchStrategy', queues: ['q1'] }).keys).to eq([:polling_strategy])
  end

  it 'accepts an unknown global name without top-level queues, as no group uses it' do
    expect(errors({ polling_strategy: 'NoSuchStrategy', queues: [], groups: { custom: { queues: ['q1'] } } }))
      .to be_empty
  end

  it 'rejects an unknown name in a group, as a Hash or as an Array of pairs' do
    expect(errors({ groups: { custom: { polling_strategy: 'NoSuchStrategy' } } }).keys)
      .to eq([:'groups.custom.polling_strategy'])
    expect(errors({ groups: [['custom', { polling_strategy: 'not a constant' }]] }).keys)
      .to eq([:'groups.custom.polling_strategy'])
  end

  it 'raises InvalidPollingStrategyError, an InvalidConfigurationError, naming every unknown name' do
    opts = { polling_strategy: 'NoSuchStrategy', queues: ['q1'], groups: { custom: { polling_strategy: 'NoSuchStrategy' } } }

    expect { described_class.new.validate!(opts) }.to raise_error(
      Shoryuken::Errors::InvalidPollingStrategyError,
      /polling_strategy.*groups\.custom\.polling_strategy.*the name of a defined class/
    )
    expect(Shoryuken::Errors::InvalidPollingStrategyError.ancestors)
      .to include(Shoryuken::Errors::InvalidConfigurationError)
  end
end
