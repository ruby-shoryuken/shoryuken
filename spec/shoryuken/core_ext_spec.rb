require 'spec_helper'

RSpec.describe 'Core Extensions' do
  describe Hash do
    describe '#stringify_keys' do
      it 'converts keys into strings' do
        expect({ :key1 => 'value1', 'key2' => 'value2' }.stringify_keys).to eq('key1' => 'value1', 'key2' => 'value2')
      end
    end

    describe '#deep_stringify_keys' do
      it 'converts keys into strings' do
        expect({ :key1 => 'value1',
                 'key2' => 'value2',
                 :key3 => {
                   'key31' => { key311: 'value311' },
                   :key32 => 'value32'
                 } }.deep_stringify_keys).to eq('key1' => 'value1',
                                                'key2' => 'value2',
                                                'key3' => {
                                                  'key31' => { 'key311' => 'value311' },
                                                  'key32' => 'value32'
                                                })
      end
    end

    describe '#symbolize_keys' do
      it 'converts keys into symbols' do
        expect({ :key1 => 'value1', 'key2' => 'value2' }.symbolize_keys).to eq(key1: 'value1', key2: 'value2')
      end
    end

    describe '#deep_symbolize_keys' do
      it 'converts keys into symbols' do
        expect({ :key1 => 'value1',
                 'key2' => 'value2',
                 'key3' => {
                   'key31' => { 'key311' => 'value311' },
                   'key32' => 'value32'
                 } }.deep_symbolize_keys).to eq(key1: 'value1',
                                                key2: 'value2',
                                                key3: { key31:                                                                                     { key311: 'value311' },
                                                        key32: 'value32' })
      end
    end
  end

  describe String do
    describe '#constantize' do
      class HelloWorld; end
      it 'returns a class from a string' do
        expect('HelloWorld'.constantize).to eq HelloWorld
      end
    end
  end

  describe Array do
    describe '#in_groups_of' do
      it 'groups element of an array without padding' do
        expect([1, 2, 3, 4, 5].in_groups_of(2, false)).to eq([[1, 2], [3, 4], [5]])
      end

      it 'groups element of an array with padding' do
        expect([1, 2, 3, 4, 5].in_groups_of(2, nil)).to eq([[1, 2], [3, 4], [5, nil]])
      end
    end
  end
end
