# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Helpers::HashUtils do
  describe '.deep_symbolize_keys' do
    it 'converts string keys to symbols' do
      input = { 'key1' => 'value1', 'key2' => 'value2' }
      expected = { key1: 'value1', key2: 'value2' }

      expect(described_class.deep_symbolize_keys(input)).to eq(expected)
    end

    it 'leaves symbol keys unchanged' do
      input = { key1: 'value1', key2: 'value2' }
      expected = { key1: 'value1', key2: 'value2' }

      expect(described_class.deep_symbolize_keys(input)).to eq(expected)
    end

    it 'handles mixed key types' do
      input = { 'string_key' => 'value1', :symbol_key => 'value2' }
      expected = { string_key: 'value1', symbol_key: 'value2' }

      expect(described_class.deep_symbolize_keys(input)).to eq(expected)
    end

    it 'converts keys recursively in nested hashes' do
      input = {
        'level1' => {
          'level2' => {
            'level3' => 'deep_value'
          },
          'other_level2' => 'value'
        },
        'top_level' => 'value'
      }

      expected = {
        level1: {
          level2: {
            level3: 'deep_value'
          },
          other_level2: 'value'
        },
        top_level: 'value'
      }

      expect(described_class.deep_symbolize_keys(input)).to eq(expected)
    end

    it 'preserves non-hash values in nested structures' do
      input = {
        'config' => {
          'timeout' => 30,
          'enabled' => true,
          'tags' => ['tag1', 'tag2'],
          'metadata' => nil
        }
      }

      expected = {
        config: {
          timeout: 30,
          enabled: true,
          tags: ['tag1', 'tag2'],
          metadata: nil
        }
      }

      expect(described_class.deep_symbolize_keys(input)).to eq(expected)
    end

    it 'handles empty hash' do
      expect(described_class.deep_symbolize_keys({})).to eq({})
    end

    it 'handles hash with empty nested hash' do
      input = { 'key' => {} }
      expected = { key: {} }

      expect(described_class.deep_symbolize_keys(input)).to eq(expected)
    end

    it 'returns non-hash input unchanged' do
      expect(described_class.deep_symbolize_keys('string')).to eq('string')
      expect(described_class.deep_symbolize_keys(123)).to eq(123)
      expect(described_class.deep_symbolize_keys([])).to eq([])
      expect(described_class.deep_symbolize_keys(nil)).to be_nil
      expect(described_class.deep_symbolize_keys(true)).to be true
    end

    it 'handles keys that cannot be converted to symbols' do
      # Create a key that will raise an exception when converted to symbol
      problematic_key = Object.new
      allow(problematic_key).to receive(:to_sym).and_raise(StandardError)

      input = { problematic_key => 'value', 'normal_key' => 'normal_value' }
      result = described_class.deep_symbolize_keys(input)

      # The problematic key should remain as-is, normal key should be symbolized
      expect(result[problematic_key]).to eq('value')
      expect(result[:normal_key]).to eq('normal_value')
    end

    it 'does not modify the original hash' do
      input = { 'key' => { 'nested' => 'value' } }
      original_input = input.dup

      described_class.deep_symbolize_keys(input)

      expect(input).to eq(original_input)
    end

    context 'with configuration-like data' do
      it 'processes typical YAML configuration' do
        input = {
          'database' => {
            'host' => 'localhost',
            'port' => 5432,
            'ssl' => true
          },
          'queues' => {
            'default' => { 'concurrency' => 5 },
            'mailers' => { 'concurrency' => 2 }
          }
        }

        expected = {
          database: {
            host: 'localhost',
            port: 5432,
            ssl: true
          },
          queues: {
            default: { concurrency: 5 },
            mailers: { concurrency: 2 }
          }
        }

        expect(described_class.deep_symbolize_keys(input)).to eq(expected)
      end
    end
  end
end