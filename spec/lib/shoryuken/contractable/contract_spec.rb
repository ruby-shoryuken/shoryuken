# frozen_string_literal: true

RSpec.describe Shoryuken::Contractable::Contract do
  subject(:contract) { contract_class.new }

  let(:contract_class) do
    Class.new(described_class) do
      self.error_messages = {
        'missing' => 'is missing',
        'format' => 'is invalid',
        'name_format' => 'needs to be a String',
        'details.size_format' => 'needs to be positive'
      }

      required(:name) { |value| value.is_a?(String) }
      optional(:mode) { |value| %i[fast slow].include?(value) }

      nested(:details) do
        required(:size) { |value| value.is_a?(Integer) && value.positive? }
      end

      virtual do |data|
        next true unless data.is_a?(Hash) && data[:name] == 'forbidden'

        [[%i[name], 'is forbidden']]
      end
    end
  end

  let(:valid) { { name: 'test', details: { size: 1 } } }

  it 'succeeds for valid data' do
    expect(contract.call(valid)).to be_success
  end

  it 'does not check an optional key that is missing' do
    expect(contract.call(valid).errors).to be_empty
  end

  it 'checks an optional key that is present' do
    expect(contract.call(valid.merge(mode: :other)).errors).to eq(mode: 'is invalid')
  end

  it 'reports a missing required key' do
    expect(contract.call({ details: { size: 1 } }).errors).to eq(name: 'is missing')
  end

  it 'resolves the message by the key path' do
    expect(contract.call({ name: 1, details: { size: 0 } }).errors)
      .to eq(name: 'needs to be a String', 'details.size': 'needs to be positive')
  end

  it 'reports a nested key as missing when its parent is not a Hash' do
    expect(contract.call({ name: 'test', details: 1 }).errors).to eq('details.size': 'is missing')
  end

  it 'collects the errors of a virtual rule' do
    expect(contract.call(valid.merge(name: 'forbidden')).errors).to eq(name: 'is forbidden')
  end

  it 'prefixes the errors with the scope' do
    expect(contract.call({ details: { size: 1 } }, scope: %i[root]).errors).to eq('root.name': 'is missing')
  end

  it 'reports every required key as missing for non-Hash data' do
    expect(contract.call(nil).errors).to eq(name: 'is missing', 'details.size': 'is missing')
  end

  describe '#validate!' do
    it 'returns true for valid data' do
      expect(contract.validate!(valid, ArgumentError)).to be(true)
    end

    it 'raises the given error with the errors for invalid data' do
      expect { contract.validate!({}, ArgumentError) }.to raise_error(ArgumentError, /name/)
    end
  end

  describe '.error_messages' do
    it 'is inherited from the parent contract' do
      expect(Class.new(contract_class).error_messages).to eq(contract_class.error_messages)
    end
  end
end
