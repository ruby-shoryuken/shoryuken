# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Helpers::ThreadPool do
  subject(:pool) { described_class.new }

  after do
    pool.kill
    pool.wait_for_termination(5)
  end

  describe '#post' do
    it 'runs the block on another thread without waiting for it' do
      ran_on = Queue.new
      release = Queue.new

      accepted = pool.post do
        ran_on << Thread.current
        release.pop
      end

      expect(accepted).to be true

      expect(ran_on.pop(timeout: 5)).not_to eq(Thread.current)
      release << true
    end

    it 'starts a new thread when every thread is busy' do
      release = Queue.new
      threads = Queue.new

      2.times do
        pool.post do
          threads << Thread.current
          release.pop
        end
      end

      expect([threads.pop(timeout: 5), threads.pop(timeout: 5)].uniq.size).to eq(2)
      2.times { release << true }
    end

    it 'reuses an idle thread' do
      threads = Queue.new

      pool.post { threads << Thread.current }
      first = threads.pop(timeout: 5)
      sleep 0.05
      pool.post { threads << Thread.current }

      expect(threads.pop(timeout: 5)).to eq(first)
    end

    it 'keeps the thread running after a block raises' do
      allow(Shoryuken.logger).to receive(:error)
      threads = Queue.new

      pool.post do
        threads << Thread.current
        raise 'block failure'
      end
      first = threads.pop(timeout: 5)
      sleep 0.05
      pool.post { threads << Thread.current }

      expect(threads.pop(timeout: 5)).to eq(first)
      expect(Shoryuken.logger).to have_received(:error)
    end

    it 'keeps the thread running after a block raises an error that is not a StandardError' do
      allow(Shoryuken.logger).to receive(:error)
      threads = Queue.new

      pool.post do
        threads << Thread.current
        raise NotImplementedError, 'block failure'
      end
      first = threads.pop(timeout: 5)
      sleep 0.05
      pool.post { threads << Thread.current }

      expect(threads.pop(timeout: 5)).to eq(first)
      expect(Shoryuken.logger).to have_received(:error)
    end

    it 'raises the error of a thread that cannot start and still shuts down' do
      allow(Thread).to receive(:new).and_raise(ThreadError, "can't create Thread")

      expect { pool.post {} }.to raise_error(ThreadError)

      pool.shutdown
      expect(pool.wait_for_termination(1)).to be true
    end

    it 'raises RejectedExecutionError once shut down' do
      pool.shutdown

      expect { pool.post {} }.to raise_error(Shoryuken::Errors::RejectedExecutionError)
    end
  end

  describe 'idle threads' do
    before { stub_const("#{described_class}::IDLE_TIMEOUT", 0.1) }

    it 'runs a block posted while its idle thread times out' do
      ran = Shoryuken::Helpers::AtomicBoolean.new(false)
      first_done = Shoryuken::Helpers::AtomicBoolean.new(false)
      posted = Shoryuken::Helpers::AtomicBoolean.new(false)

      # Posts right after the idle thread's wait times out and before it decides to exit, so the
      # post hands the block to that thread instead of starting a new one
      allow_any_instance_of(Thread::Queue).to receive(:pop).and_wrap_original do |original, *args, **kwargs|
        task = original.call(*args, **kwargs)
        if task.nil? && kwargs.key?(:timeout) && first_done.true? && !posted.true?
          posted.make_true
          pool.post { ran.make_true }
        end
        task
      end

      pool.post { first_done.make_true }

      50.times do
        break if ran.true?

        sleep 0.05
      end

      expect(posted.true?).to be true
      expect(ran.true?).to be true
    end

    it 'exits an idle thread after the idle timeout and starts a new one for the next block' do
      threads = Queue.new

      pool.post { threads << Thread.current }
      first = threads.pop(timeout: 5)

      expect(first.join(5)).to eq(first)

      pool.post { threads << Thread.current }
      expect(threads.pop(timeout: 5)).not_to eq(first)
    end
  end

  describe '#shutdown' do
    it 'stops accepting blocks and lets the posted ones finish' do
      done = Shoryuken::Helpers::AtomicBoolean.new(false)
      pool.post do
        sleep 0.2
        done.make_true
      end

      pool.shutdown

      expect(pool).not_to be_running
      expect(pool.wait_for_termination(5)).to be true
      expect(done.true?).to be true
    end
  end

  describe '#wait_for_termination' do
    it 'waits for a thread that a post before the shutdown is still starting' do
      starting = Queue.new
      done = Shoryuken::Helpers::AtomicBoolean.new(false)
      allow(Thread).to receive(:new).and_wrap_original do |original, *args, &block|
        starting << true
        sleep 0.2
        original.call(*args, &block)
      end

      poster = Thread.start do
        pool.post do
          sleep 0.1
          done.make_true
        end
      end
      starting.pop(timeout: 5)

      pool.shutdown

      expect(pool.wait_for_termination(5)).to be true
      expect(done.true?).to be true
      poster.join(5)
    end

    it 'returns true at once when no thread was started' do
      pool.shutdown

      expect(pool.wait_for_termination(0)).to be true
    end

    it 'returns false when a block runs past the timeout' do
      pool.post { sleep 2 }
      pool.shutdown

      expect(pool.wait_for_termination(0.1)).to be false
    end
  end

  describe '#kill' do
    let(:marker_class) { Class.new }

    def post_marked_block(pool, marker_class)
      marker = marker_class.new
      pool.post { marker }
    end

    it 'releases the blocks posted but not started' do
      idle = Shoryuken::Helpers::AtomicBoolean.new(false)
      # Keeps the idle thread from taking the next block until the pool is killed
      allow_any_instance_of(Thread::Queue).to receive(:pop).and_wrap_original do |original, *args, **kwargs|
        if kwargs.key?(:timeout)
          idle.make_true
          sleep 1
        end
        original.call(*args, **kwargs)
      end
      pool.post {}
      sleep 0.01 until idle.true?

      post_marked_block(pool, marker_class)
      pool.kill
      pool.wait_for_termination(5)
      GC.start

      expect(ObjectSpace.each_object(marker_class).count).to eq(0)
    end

    it 'stops the running blocks and drops the queued ones' do
      started = Queue.new
      ran = Shoryuken::Helpers::AtomicBoolean.new(false)
      pool.post do
        started << true
        sleep 10
      end
      started.pop(timeout: 5)

      pool.kill

      expect(pool).not_to be_running
      expect(pool.wait_for_termination(5)).to be true
      expect { pool.post { ran.make_true } }.to raise_error(Shoryuken::Errors::RejectedExecutionError)
      expect(ran.true?).to be false
    end
  end
end
