# frozen_string_literal: true

RSpec.describe 'Helpers Integration' do
  # Integration tests for helper utility methods that replaced core extensions

  describe Shoryuken::Helpers::HashUtils do
    describe '.deep_symbolize_keys' do
      it 'converts keys into symbols recursively' do
        input = { :key1 => 'value1',
                 'key2' => 'value2',
                 'key3' => {
                   'key31' => { 'key311' => 'value311' },
                   'key32' => 'value32'
                 } }

        expected = { key1: 'value1',
                    key2: 'value2',
                    key3: { key31: { key311: 'value311' },
                            key32: 'value32' } }

        expect(Shoryuken::Helpers::HashUtils.deep_symbolize_keys(input)).to eq(expected)
      end

      it 'handles non-hash input gracefully' do
        expect(Shoryuken::Helpers::HashUtils.deep_symbolize_keys('string')).to eq('string')
        expect(Shoryuken::Helpers::HashUtils.deep_symbolize_keys(123)).to eq(123)
        expect(Shoryuken::Helpers::HashUtils.deep_symbolize_keys(nil)).to be_nil
      end

      it 'handles empty hash' do
        expect(Shoryuken::Helpers::HashUtils.deep_symbolize_keys({})).to eq({})
      end

      it 'handles mixed value types' do
        input = { 'key1' => 'string', 'key2' => 123, 'key3' => { 'nested' => true } }
        expected = { key1: 'string', key2: 123, key3: { nested: true } }

        expect(Shoryuken::Helpers::HashUtils.deep_symbolize_keys(input)).to eq(expected)
      end
    end
  end

  describe Shoryuken::Helpers::StringUtils do
    describe '.constantize' do
      class HelloWorld; end

      it 'returns a class from a string' do
        expect(Shoryuken::Helpers::StringUtils.constantize('HelloWorld')).to eq(HelloWorld)
      end

      it 'handles nested constants' do
        expect(Shoryuken::Helpers::StringUtils.constantize('Shoryuken::Helpers::StringUtils')).to eq(Shoryuken::Helpers::StringUtils)
      end

      it 'raises NameError for non-existent constants' do
        expect { Shoryuken::Helpers::StringUtils.constantize('NonExistentClass') }.to raise_error(NameError)
      end

      it 'handles empty string' do
        expect(Shoryuken::Helpers::StringUtils.constantize('')).to eq(Object)
      end

      it 'handles leading double colon' do
        expect(Shoryuken::Helpers::StringUtils.constantize('::Object')).to eq(Object)
      end
    end
  end

  describe 'Integration scenarios' do
    it 'processes configuration data end-to-end' do
      # Simulate loading YAML config and converting worker class names
      config_data = {
        'queues' => {
          'default' => { 'worker_class' => 'Object' },
          'mailers' => { 'worker_class' => 'String' }
        }
      }

      symbolized = Shoryuken::Helpers::HashUtils.deep_symbolize_keys(config_data)

      expect(symbolized).to eq({
        queues: {
          default: { worker_class: 'Object' },
          mailers: { worker_class: 'String' }
        }
      })

      # Test constantizing the worker classes
      default_worker = Shoryuken::Helpers::StringUtils.constantize(symbolized[:queues][:default][:worker_class])
      mailer_worker = Shoryuken::Helpers::StringUtils.constantize(symbolized[:queues][:mailers][:worker_class])

      expect(default_worker).to eq(Object)
      expect(mailer_worker).to eq(String)
    end
  end
end
