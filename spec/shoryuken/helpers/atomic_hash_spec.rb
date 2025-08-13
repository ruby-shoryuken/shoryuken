require 'spec_helper'
require 'shoryuken/helpers/atomic_hash'

RSpec.describe Shoryuken::Helpers::AtomicHash do
  subject { described_class.new }

  describe '#initialize' do
    it 'creates an empty hash' do
      hash = described_class.new
      expect(hash.keys).to eq([])
    end
  end

  describe '#[]' do
    it 'returns nil for missing keys' do
      expect(subject['missing']).to be_nil
    end

    it 'returns stored values' do
      subject['key'] = 'value'
      expect(subject['key']).to eq('value')
    end

    it 'works with different key types' do
      subject[:symbol] = 'symbol_value'
      subject[42] = 'number_value'
      
      expect(subject[:symbol]).to eq('symbol_value')
      expect(subject[42]).to eq('number_value')
    end
  end

  describe '#[]=' do
    it 'stores values' do
      subject['key'] = 'value'
      expect(subject['key']).to eq('value')
    end

    it 'overwrites existing values' do
      subject['key'] = 'old_value'
      subject['key'] = 'new_value'
      expect(subject['key']).to eq('new_value')
    end

    it 'returns the assigned value' do
      result = (subject['key'] = 'value')
      expect(result).to eq('value')
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      subject['key1'] = 'value1'
      subject['key2'] = 'value2'
      
      expect(subject.keys.size).to eq(2)
      
      subject.clear
      
      expect(subject.keys).to eq([])
      expect(subject['key1']).to be_nil
      expect(subject['key2']).to be_nil
    end

    it 'returns the hash itself' do
      subject['key'] = 'value'
      result = subject.clear
      expect(result).to eq({})
    end
  end

  describe '#keys' do
    it 'returns empty array for empty hash' do
      expect(subject.keys).to eq([])
    end

    it 'returns all keys' do
      subject['key1'] = 'value1'
      subject[:key2] = 'value2'
      subject[42] = 'value3'
      
      keys = subject.keys
      expect(keys).to contain_exactly('key1', :key2, 42)
    end

    it 'reflects changes after modifications' do
      subject['key'] = 'value'
      expect(subject.keys).to eq(['key'])
      
      subject.clear
      expect(subject.keys).to eq([])
    end
  end

  describe '#fetch' do
    it 'returns value for existing key' do
      subject['key'] = 'value'
      expect(subject.fetch('key')).to eq('value')
    end

    it 'returns default for missing key' do
      expect(subject.fetch('missing', 'default')).to eq('default')
    end

    it 'returns nil as default when no default provided' do
      expect(subject.fetch('missing')).to be_nil
    end

    it 'works with different default types' do
      expect(subject.fetch('missing', [])).to eq([])
      expect(subject.fetch('missing', {})).to eq({})
      expect(subject.fetch('missing', 42)).to eq(42)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent writes correctly' do
      hash = described_class.new
      threads = []
      
      # 10 threads, each writing 100 different keys
      10.times do |thread_id|
        threads << Thread.new do
          100.times do |i|
            key = "thread_#{thread_id}_key_#{i}"
            hash[key] = "value_#{i}"
          end
        end
      end
      
      threads.each(&:join)
      
      # Verify all 1000 keys were written
      expect(hash.keys.size).to eq(1000)
      
      # Verify a sample of values
      expect(hash['thread_0_key_0']).to eq('value_0')
      expect(hash['thread_9_key_99']).to eq('value_99')
    end

    it 'handles concurrent reads correctly' do
      hash = described_class.new
      
      # Pre-populate hash
      100.times { |i| hash["key_#{i}"] = "value_#{i}" }
      
      read_results = []
      threads = []
      
      # 10 threads, each reading 100 times
      10.times do
        threads << Thread.new do
          100.times do |i|
            key = "key_#{i % 100}"
            read_results << hash[key]
          end
        end
      end
      
      threads.each(&:join)
      
      # All reads should succeed
      expect(read_results.size).to eq(1000)
      expect(read_results.compact.size).to eq(1000)
    end

    it 'handles mixed concurrent read/write operations' do
      hash = described_class.new
      threads = []
      
      # Writer threads
      5.times do |thread_id|
        threads << Thread.new do
          50.times do |i|
            hash["writer_#{thread_id}_#{i}"] = "value_#{i}"
          end
        end
      end
      
      # Reader threads
      5.times do
        threads << Thread.new do
          100.times do |i|
            # Read existing keys
            hash["writer_0_#{i % 50}"]
          end
        end
      end
      
      # Clear operations
      2.times do
        threads << Thread.new do
          sleep(0.001) # Let some writes happen first
          hash.clear
        end
      end
      
      threads.each(&:join)
      
      # The hash should be valid (not corrupted)
      # After clear operations, it might be empty or have some keys
      expect(hash.keys).to be_an(Array)
    end

    it 'provides thread-safe key enumeration' do
      hash = described_class.new
      threads = []
      keys_snapshots = []
      
      # Writer thread
      writer = Thread.new do
        100.times { |i| hash["key_#{i}"] = i }
      end
      
      # Reader threads taking snapshots of keys
      5.times do
        threads << Thread.new do
          20.times do
            keys_snapshots << hash.keys.dup
          end
        end
      end
      
      [writer, *threads].each(&:join)
      
      # All snapshots should be valid arrays
      keys_snapshots.each do |snapshot|
        expect(snapshot).to be_an(Array)
        # Keys should be valid
        snapshot.each { |key| expect(key).to be_a(String) }
      end
    end
  end

  describe 'drop-in replacement for Concurrent::Hash' do
    it 'provides the same basic API' do
      # Test that our implementation has the same methods as Concurrent::Hash
      expect(subject).to respond_to(:[])
      expect(subject).to respond_to(:[]=)
      expect(subject).to respond_to(:clear)
      expect(subject).to respond_to(:keys)
      expect(subject).to respond_to(:fetch)
    end

    it 'behaves identically to Concurrent::Hash for basic operations' do
      # This test documents the expected behavior that matches Concurrent::Hash
      hash = described_class.new
      
      # Test assignment and retrieval
      hash['queue1'] = 'Worker1'
      expect(hash['queue1']).to eq('Worker1')
      
      # Test keys
      expect(hash.keys).to eq(['queue1'])
      
      # Test fetch with default
      expect(hash.fetch('queue1')).to eq('Worker1')
      expect(hash.fetch('missing', 'default')).to eq('default')
      
      # Test clear
      hash.clear
      expect(hash.keys).to eq([])
      expect(hash['queue1']).to be_nil
    end

    it 'matches DefaultWorkerRegistry usage patterns' do
      # Test the exact patterns used in DefaultWorkerRegistry
      hash = described_class.new
      
      # Pattern from register_worker method
      queue = 'test_queue'
      clazz = 'TestWorker'
      hash[queue] = clazz
      
      # Pattern from batch_receive_messages? method
      expect(hash[queue]).to eq(clazz)
      
      # Pattern from fetch_worker method  
      expect(hash[queue]).to eq(clazz)
      
      # Pattern from queues method
      expect(hash.keys).to eq([queue])
      
      # Pattern from workers method (with fetch and default)
      expect(hash.fetch(queue, [])).to eq(clazz)
      expect(hash.fetch('missing', [])).to eq([])
      
      # Pattern from clear method
      hash.clear
      expect(hash.keys).to eq([])
    end
  end
end