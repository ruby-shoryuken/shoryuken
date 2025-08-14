# frozen_string_literal: true

RSpec.describe Shoryuken::Helpers::AtomicCounter do
  subject { described_class.new }

  describe '#initialize' do
    it 'initializes with default value of 0' do
      counter = described_class.new
      expect(counter.value).to eq(0)
    end

    it 'initializes with custom value' do
      counter = described_class.new(42)
      expect(counter.value).to eq(42)
    end

    it 'initializes with negative value' do
      counter = described_class.new(-10)
      expect(counter.value).to eq(-10)
    end
  end

  describe '#value' do
    it 'returns the current value' do
      expect(subject.value).to eq(0)
    end

    it 'returns the updated value after operations' do
      subject.increment
      expect(subject.value).to eq(1)

      subject.decrement
      expect(subject.value).to eq(0)
    end
  end

  describe '#increment' do
    it 'increments the counter by 1' do
      expect { subject.increment }.to change { subject.value }.from(0).to(1)
    end

    it 'returns the new value' do
      result = subject.increment
      expect(result).to eq(1)
    end

    it 'can be called multiple times' do
      3.times { subject.increment }
      expect(subject.value).to eq(3)
    end

    it 'works with negative initial values' do
      counter = described_class.new(-5)
      counter.increment
      expect(counter.value).to eq(-4)
    end
  end

  describe '#decrement' do
    it 'decrements the counter by 1' do
      subject.increment # Start at 1
      expect { subject.decrement }.to change { subject.value }.from(1).to(0)
    end

    it 'returns the new value' do
      subject.increment # Start at 1
      result = subject.decrement
      expect(result).to eq(0)
    end

    it 'can go negative' do
      subject.decrement
      expect(subject.value).to eq(-1)
    end

    it 'can be called multiple times' do
      3.times { subject.decrement }
      expect(subject.value).to eq(-3)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent increments correctly' do
      counter = described_class.new
      threads = []

      10.times do
        threads << Thread.new do
          100.times { counter.increment }
        end
      end

      threads.each(&:join)
      expect(counter.value).to eq(1000)
    end

    it 'handles concurrent decrements correctly' do
      counter = described_class.new(1000)
      threads = []

      10.times do
        threads << Thread.new do
          100.times { counter.decrement }
        end
      end

      threads.each(&:join)
      expect(counter.value).to eq(0)
    end

    it 'handles mixed concurrent operations correctly' do
      counter = described_class.new
      threads = []

      # 5 threads incrementing
      5.times do
        threads << Thread.new do
          100.times { counter.increment }
        end
      end

      # 3 threads decrementing
      3.times do
        threads << Thread.new do
          100.times { counter.decrement }
        end
      end

      threads.each(&:join)
      expect(counter.value).to eq(200) # 500 increments - 300 decrements
    end

    it 'provides atomic read operations' do
      counter = described_class.new
      values_read = []

      # Writer thread
      writer = Thread.new do
        1000.times { counter.increment }
      end

      # Reader threads
      readers = 5.times.map do
        Thread.new do
          100.times { values_read << counter.value }
        end
      end

      [writer, *readers].each(&:join)

      # All read values should be valid integers (not partial writes)
      expect(values_read).to all(be_an(Integer))
      expect(values_read).to all(be >= 0)
      expect(values_read).to all(be <= 1000)
    end
  end

  describe 'drop-in replacement for Concurrent::AtomicFixnum' do
    it 'provides the same basic API' do
      # Test that our implementation has the same methods as Concurrent::AtomicFixnum
      expect(subject).to respond_to(:value)
      expect(subject).to respond_to(:increment)
      expect(subject).to respond_to(:decrement)
    end

    it 'behaves identically to Concurrent::AtomicFixnum for basic operations' do
      # This test documents the expected behavior that matches Concurrent::AtomicFixnum
      counter = described_class.new(5)

      expect(counter.value).to eq(5)
      expect(counter.increment).to eq(6)
      expect(counter.value).to eq(6)
      expect(counter.decrement).to eq(5)
      expect(counter.value).to eq(5)
    end
  end
end
