require 'spec_helper'
require 'shoryuken/helpers/atomic_boolean'

RSpec.describe Shoryuken::Helpers::AtomicBoolean do
  subject { described_class.new }

  describe '#initialize' do
    it 'initializes with default value of false' do
      boolean = described_class.new
      expect(boolean.value).to eq(false)
    end

    it 'initializes with true value' do
      boolean = described_class.new(true)
      expect(boolean.value).to eq(true)
    end

    it 'initializes with false value' do
      boolean = described_class.new(false)
      expect(boolean.value).to eq(false)
    end

    it 'converts truthy values to true' do
      boolean = described_class.new('truthy')
      expect(boolean.value).to eq(true)
    end

    it 'converts falsy values to false' do
      boolean = described_class.new(nil)
      expect(boolean.value).to eq(false)
    end
  end

  describe '#value' do
    it 'returns the current value' do
      expect(subject.value).to eq(false)
    end

    it 'returns the updated value after operations' do
      subject.make_true
      expect(subject.value).to eq(true)

      subject.make_false
      expect(subject.value).to eq(false)
    end
  end

  describe '#make_true' do
    it 'sets the value to true' do
      expect { subject.make_true }.to change { subject.value }.from(false).to(true)
    end

    it 'returns true' do
      result = subject.make_true
      expect(result).to eq(true)
    end

    it 'keeps the value true if already true' do
      subject.make_true
      expect { subject.make_true }.not_to change { subject.value }
      expect(subject.value).to eq(true)
    end
  end

  describe '#make_false' do
    it 'sets the value to false' do
      subject.make_true # Start with true
      expect { subject.make_false }.to change { subject.value }.from(true).to(false)
    end

    it 'returns false' do
      result = subject.make_false
      expect(result).to eq(false)
    end

    it 'keeps the value false if already false' do
      expect { subject.make_false }.not_to change { subject.value }
      expect(subject.value).to eq(false)
    end
  end

  describe '#true?' do
    it 'returns true when value is true' do
      subject.make_true
      expect(subject.true?).to eq(true)
    end

    it 'returns false when value is false' do
      expect(subject.true?).to eq(false)
    end
  end

  describe '#false?' do
    it 'returns true when value is false' do
      expect(subject.false?).to eq(true)
    end

    it 'returns false when value is true' do
      subject.make_true
      expect(subject.false?).to eq(false)
    end
  end


  describe 'thread safety' do
    it 'handles concurrent make_true operations correctly' do
      boolean = described_class.new(false)
      threads = []

      10.times do
        threads << Thread.new do
          100.times { boolean.make_true }
        end
      end

      threads.each(&:join)
      expect(boolean.value).to eq(true)
    end

    it 'handles concurrent make_false operations correctly' do
      boolean = described_class.new(true)
      threads = []

      10.times do
        threads << Thread.new do
          100.times { boolean.make_false }
        end
      end

      threads.each(&:join)
      expect(boolean.value).to eq(false)
    end

    it 'handles mixed concurrent operations correctly' do
      boolean = described_class.new(false)
      threads = []
      results = []

      # Multiple threads setting to true and false
      10.times do
        threads << Thread.new do
          50.times do
            boolean.make_true
            boolean.make_false
          end
        end
      end

      # Reader threads
      5.times do
        threads << Thread.new do
          100.times { results << boolean.value }
        end
      end

      threads.each(&:join)

      # All read values should be valid booleans
      expect(results).to all(satisfy { |v| v == true || v == false })
    end

  end

  describe 'drop-in replacement for Concurrent::AtomicBoolean' do
    it 'provides the same basic API' do
      # Test that our implementation has the same methods as Concurrent::AtomicBoolean
      expect(subject).to respond_to(:value)
      expect(subject).to respond_to(:make_true)
      expect(subject).to respond_to(:make_false)
      expect(subject).to respond_to(:true?)
      expect(subject).to respond_to(:false?)
    end

    it 'behaves identically to Concurrent::AtomicBoolean for basic operations' do
      # This test documents the expected behavior that matches Concurrent::AtomicBoolean
      boolean = described_class.new(false)

      expect(boolean.value).to eq(false)
      expect(boolean.false?).to eq(true)
      expect(boolean.true?).to eq(false)

      boolean.make_true
      expect(boolean.value).to eq(true)
      expect(boolean.true?).to eq(true)
      expect(boolean.false?).to eq(false)

      boolean.make_false
      expect(boolean.value).to eq(false)
      expect(boolean.false?).to eq(true)
      expect(boolean.true?).to eq(false)
    end
  end
end
