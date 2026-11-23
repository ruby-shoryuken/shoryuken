# frozen_string_literal: true

require 'async'

RSpec.describe Shoryuken::Helpers::FiberExecutor do
  subject(:executor) { described_class.new(limit) }

  let(:limit) { 2 }

  after do
    executor.shutdown
    executor.wait_for_termination(5)
  end

  describe '#post' do
    it 'runs the block as a task under a Fiber scheduler, not on the calling thread' do
      ran = ::Queue.new

      executor.post { ran << [Fiber.scheduler, Thread.current] }
      scheduler, thread = ran.pop

      expect(scheduler).to be_a(Async::Scheduler)
      expect(thread).not_to eq(Thread.current)
    end

    it 'runs every block on one thread' do
      threads = ::Queue.new

      5.times { executor.post { threads << Thread.current } }

      expect(Array.new(5) { threads.pop }.uniq.size).to eq(1)
    end

    it 'runs no more than limit blocks at once' do
      running = Shoryuken::Helpers::AtomicCounter.new(0)
      peaks = ::Queue.new

      6.times do
        executor.post do
          peaks << running.increment
          sleep(0.05)
          running.decrement
        end
      end
      executor.shutdown
      executor.wait_for_termination(5)

      expect(Array.new(6) { peaks.pop }.max).to eq(limit)
    end

    it 'raises Concurrent::RejectedExecutionError once shut down' do
      executor.shutdown

      expect { executor.post {} }.to raise_error(Concurrent::RejectedExecutionError)
    end
  end

  describe '#wait_for_termination' do
    it 'returns true when nothing was posted' do
      executor.shutdown

      expect(executor.wait_for_termination(1)).to be(true)
    end

    it 'waits for the queued and running blocks after a shutdown' do
      done = Shoryuken::Helpers::AtomicCounter.new(0)

      4.times { executor.post { sleep(0.05) && done.increment } }
      executor.shutdown

      expect(executor.wait_for_termination(5)).to be(true)
      expect(done.value).to eq(4)
    end

    it 'returns false when the blocks do not finish within the timeout' do
      executor.post { sleep(1) }
      executor.shutdown

      expect(executor.wait_for_termination(0.05)).to be(false)
      executor.kill
    end
  end

  describe '#running?' do
    it 'is false once shut down' do
      expect { executor.shutdown }.to change(executor, :running?).from(true).to(false)
    end
  end

  context 'when the async gem is missing' do
    before { executor }

    it 'raises an InvalidConfigurationError that names the gem' do
      allow_any_instance_of(described_class).to receive(:require).and_call_original
      allow_any_instance_of(described_class)
        .to receive(:require).with('async').and_raise(LoadError, 'cannot load such file -- async')

      expect { described_class.new(1) }.to raise_error(
        Shoryuken::Errors::InvalidConfigurationError,
        "The fiber executor needs the async gem. Add `gem 'async'` to your Gemfile (cannot load such file -- async)"
      )
    end
  end
end
