# frozen_string_literal: true

require 'shoryuken/middleware/entry'

RSpec.describe Shoryuken::Middleware::Entry do
  describe '#initialize' do
    it 'stores the middleware class' do
      entry = described_class.new(String)
      expect(entry.klass).to eq String
    end

    it 'stores initialization arguments' do
      entry = described_class.new(String, 'arg1', 'arg2')
      expect(entry.instance_variable_get(:@args)).to eq ['arg1', 'arg2']
    end
  end

  describe '#make_new' do
    let(:test_class) do
      Class.new do
        attr_reader :args

        def initialize(*args)
          @args = args
        end
      end
    end

    it 'creates a new instance of the stored class without arguments' do
      entry = described_class.new(test_class)
      instance = entry.make_new

      expect(instance).to be_a test_class
      expect(instance.args).to eq []
    end

    it 'creates a new instance with stored arguments' do
      entry = described_class.new(test_class, 'arg1', 42, { key: 'value' })
      instance = entry.make_new

      expect(instance).to be_a test_class
      expect(instance.args).to eq ['arg1', 42, { key: 'value' }]
    end

    it 'creates a new instance each time it is called' do
      entry = described_class.new(test_class, 'shared_arg')
      instance1 = entry.make_new
      instance2 = entry.make_new

      expect(instance1).to be_a test_class
      expect(instance2).to be_a test_class
      expect(instance1).not_to be instance2
      expect(instance1.args).to eq instance2.args
    end
  end

  describe '#klass' do
    it 'returns the stored class' do
      entry = described_class.new(Array)
      expect(entry.klass).to eq Array
    end

    it 'is readable' do
      entry = described_class.new(Hash)
      expect(entry.klass).to eq Hash
    end
  end
end