# frozen_string_literal: true

RSpec.describe Shoryuken::Contracts::Worker do
  def errors(opts)
    described_class.new.call(opts).errors
  end

  it 'accepts every known worker option' do
    opts = described_class::KNOWN_KEYS.to_h { |key| [key, nil] }

    expect(errors(opts)).to be_empty
  end

  it 'accepts Symbol keys' do
    expect(errors(queue: 'default', auto_delete: true)).to be_empty
  end

  it 'reports each unknown key' do
    expect(errors('queue' => 'default', 'auto_delte' => true, 'sqs' => {})).to eq(
      auto_delte: 'is not a known worker option',
      sqs: 'is not a known worker option'
    )
  end

  it 'prefixes the keys with the scope' do
    expect { described_class.new.validate!({ 'batchh' => true }, scope: ['MyWorker']) }
      .to raise_error(Shoryuken::Errors::InvalidConfigurationError, /MyWorker\.batchh/)
  end
end
