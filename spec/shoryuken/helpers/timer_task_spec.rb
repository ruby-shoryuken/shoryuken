# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Helpers::TimerTask do
  let(:execution_interval) { 0.1 }
  let(:execution_count) { 0 }
  let(:timer_task) do
    described_class.new(execution_interval: execution_interval) do
      @execution_count = (@execution_count || 0) + 1
    end
  end

  describe '#initialize' do
    it 'creates a timer task with the specified interval' do
      timer = described_class.new(execution_interval: 5) { }
      expect(timer).to be_a(described_class)
    end

    it 'requires a block' do
      expect { described_class.new(execution_interval: 5) }.to raise_error(LocalJumpError)
    end
  end

  describe '#execute' do
    it 'returns self for method chaining' do
      result = timer_task.execute
      expect(result).to eq(timer_task)
      timer_task.kill
    end

    it 'does not start multiple times' do
      timer_task.execute
      first_thread = timer_task.instance_variable_get(:@thread)
      timer_task.execute
      second_thread = timer_task.instance_variable_get(:@thread)
      expect(first_thread).to eq(second_thread)
      timer_task.kill
    end
  end

  describe '#kill' do
    it 'returns true when successfully killed' do
      timer_task.execute
      expect(timer_task.kill).to be true
    end

    it 'returns false when already killed' do
      timer_task.execute
      timer_task.kill
      expect(timer_task.kill).to be false
    end

    it 'is safe to call multiple times' do
      timer_task.execute
      expect { timer_task.kill }.not_to raise_error
      expect { timer_task.kill }.not_to raise_error
    end
  end

  describe 'execution behavior' do
    it 'executes the block at the specified interval' do
      execution_count = 0
      timer = described_class.new(execution_interval: 0.05) do
        execution_count += 1
      end

      timer.execute
      sleep(0.15) # Should allow for ~3 executions
      timer.kill

      expect(execution_count).to be >= 2
      expect(execution_count).to be <= 4 # Allow some timing variance
    end

    it 'handles exceptions in the block gracefully' do
      error_count = 0
      timer = described_class.new(execution_interval: 0.05) do
        error_count += 1
        raise StandardError, "Test error"
      end

      # Capture stderr to check for error messages
      original_stderr = $stderr
      $stderr = StringIO.new

      timer.execute
      sleep(0.15)
      timer.kill

      error_output = $stderr.string
      $stderr = original_stderr

      expect(error_count).to be >= 2
      expect(error_output).to include("TimerTask execution error: Test error")
    end

    it 'stops execution when killed' do
      execution_count = 0
      timer = described_class.new(execution_interval: 0.05) do
        execution_count += 1
      end

      timer.execute
      sleep(0.1)
      initial_count = execution_count
      timer.kill
      sleep(0.1)
      final_count = execution_count

      expect(final_count).to eq(initial_count)
    end
  end

  describe 'thread safety' do
    it 'can be safely accessed from multiple threads' do
      timer = described_class.new(execution_interval: 0.1) { }

      threads = 10.times.map do
        Thread.new do
          timer.execute
          sleep(0.01)
          timer.kill
        end
      end

      threads.each(&:join)
      # Timer should be stopped after all threads complete
      expect(timer.instance_variable_get(:@killed)).to be true
    end
  end
end
