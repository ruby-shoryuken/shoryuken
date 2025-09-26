# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Helpers::TimerTask do
  let(:execution_interval) { 0.1 }
  let!(:timer_task) do
    described_class.new(execution_interval: execution_interval) do
      @execution_count = (@execution_count || 0) + 1
    end
  end

  describe '#initialize' do
    it 'creates a timer task with the specified interval' do
      timer = described_class.new(execution_interval: 5) {}
      expect(timer).to be_a(described_class)
    end

    it 'requires a block' do
      expect { described_class.new(execution_interval: 5) }.to raise_error(ArgumentError, 'A block must be provided')
    end

    it 'requires a positive execution_interval' do
      expect { described_class.new(execution_interval: 0) {} }.to raise_error(ArgumentError, 'execution_interval must be positive')
      expect { described_class.new(execution_interval: -1) {} }.to raise_error(ArgumentError, 'execution_interval must be positive')
    end

    it 'accepts string numbers as execution_interval' do
      timer = described_class.new(execution_interval: '5.5') {}
      expect(timer.instance_variable_get(:@execution_interval)).to eq(5.5)
    end

    it 'raises ArgumentError for non-numeric execution_interval' do
      expect { described_class.new(execution_interval: 'invalid') {} }.to raise_error(ArgumentError)
      expect { described_class.new(execution_interval: nil) {} }.to raise_error(TypeError)
      expect { described_class.new(execution_interval: {}) {} }.to raise_error(TypeError)
    end

    it 'stores the task block in @task instance variable' do
      task_proc = proc { puts 'test' }
      timer = described_class.new(execution_interval: 1, &task_proc)
      expect(timer.instance_variable_get(:@task)).to eq(task_proc)
    end

    it 'stores the execution interval' do
      timer = described_class.new(execution_interval: 5) {}
      expect(timer.instance_variable_get(:@execution_interval)).to eq(5)
    end

    it 'initializes state variables correctly' do
      timer = described_class.new(execution_interval: 1) {}
      expect(timer.instance_variable_get(:@running)).to be false
      expect(timer.instance_variable_get(:@killed)).to be false
      expect(timer.instance_variable_get(:@thread)).to be_nil
    end
  end

  describe '#execute' do
    it 'returns self for method chaining' do
      result = timer_task.execute
      expect(result).to eq(timer_task)
      timer_task.kill
    end

    it 'sets @running to true when executed' do
      timer_task.execute
      expect(timer_task.instance_variable_get(:@running)).to be true
      timer_task.kill
    end

    it 'creates a new thread' do
      timer_task.execute
      thread = timer_task.instance_variable_get(:@thread)
      expect(thread).to be_a(Thread)
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

    it 'does not execute if already killed' do
      timer_task.instance_variable_set(:@killed, true)
      result = timer_task.execute
      expect(result).to eq(timer_task)
      expect(timer_task.instance_variable_get(:@thread)).to be_nil
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

    it 'sets @killed to true' do
      timer_task.execute
      timer_task.kill
      expect(timer_task.instance_variable_get(:@killed)).to be true
    end

    it 'sets @running to false' do
      timer_task.execute
      timer_task.kill
      expect(timer_task.instance_variable_get(:@running)).to be false
    end

    it 'kills the thread if alive' do
      timer_task.execute
      thread = timer_task.instance_variable_get(:@thread)
      timer_task.kill
      sleep(0.01) # Give time for thread to be killed
      expect(thread.alive?).to be false
    end

    it 'is safe to call multiple times' do
      timer_task.execute
      expect { timer_task.kill }.not_to raise_error
      expect { timer_task.kill }.not_to raise_error
    end

    it 'handles case when thread is nil' do
      timer = described_class.new(execution_interval: 1) {}
      result = nil
      expect { result = timer.kill }.not_to raise_error
      expect(result).to be true
    end
  end

  describe 'execution behavior' do
    it 'executes the task at the specified interval' do
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

    it 'calls the task block correctly' do
      task_called = false
      timer = described_class.new(execution_interval: 0.05) do
        task_called = true
      end

      timer.execute
      sleep(0.1)
      timer.kill

      expect(task_called).to be true
    end

    it 'handles exceptions in the task gracefully' do
      error_count = 0
      timer = described_class.new(execution_interval: 0.05) do
        error_count += 1
        raise StandardError, 'Test error'
      end

      # Capture stderr to check for error messages
      original_stderr = $stderr
      captured_stderr = StringIO.new
      $stderr = captured_stderr

      # Mock warn method to prevent warning gem from raising exceptions
      # but still capture the output
      allow_any_instance_of(Object).to receive(:warn) do |*args|
        captured_stderr.puts(*args)
      end

      timer.execute
      sleep(0.15)
      timer.kill

      error_output = captured_stderr.string
      $stderr = original_stderr

      expect(error_count).to be >= 2
      expect(error_output).to include('Test error')
    end

    it 'continues execution after exceptions' do
      execution_count = 0
      timer = described_class.new(execution_interval: 0.05) do
        execution_count += 1
        raise StandardError, 'Test error' if execution_count == 1
      end

      # Mock warn method to prevent warning gem from raising exceptions
      allow_any_instance_of(Object).to receive(:warn)

      timer.execute
      sleep(0.15)
      timer.kill

      expect(execution_count).to be >= 2 # Should continue after first error
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

    it 'respects the execution interval' do
      execution_times = []
      timer = described_class.new(execution_interval: 0.1) do
        execution_times << Time.now
      end

      timer.execute
      sleep(0.35) # Allow for ~3 executions
      timer.kill

      expect(execution_times.length).to be >= 2
      if execution_times.length >= 2
        interval = execution_times[1] - execution_times[0]
        expect(interval).to be_within(0.05).of(0.1)
      end
    end
  end

  describe 'thread safety' do
    it 'can be safely accessed from multiple threads' do
      timer = described_class.new(execution_interval: 0.1) {}

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

    it 'handles concurrent execute calls safely' do
      timer = described_class.new(execution_interval: 0.1) {}

      threads = 5.times.map do
        Thread.new { timer.execute }
      end

      threads.each(&:join)

      # Should only have one thread created
      expect(timer.instance_variable_get(:@thread)).to be_a(Thread)
      timer.kill
    end

    it 'handles concurrent kill calls safely' do
      timer = described_class.new(execution_interval: 0.1) {}
      timer.execute

      threads = 5.times.map do
        Thread.new { timer.kill }
      end

      results = threads.map(&:value)

      # Only one kill should return true, others should return false
      true_count = results.count(true)
      false_count = results.count(false)

      expect(true_count).to eq(1)
      expect(false_count).to eq(4)
    end
  end
end
