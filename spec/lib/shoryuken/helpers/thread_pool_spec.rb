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

      expect(pool.post { ran_on << Thread.current and release.pop }).to be true

      expect(ran_on.pop(timeout: 5)).not_to eq(Thread.current)
      release << true
    end

    it 'starts a new thread when every thread is busy' do
      release = Queue.new
      threads = Queue.new

      2.times { pool.post { threads << Thread.current and release.pop } }

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

    it 'raises RejectedExecutionError once shut down' do
      pool.shutdown

      expect { pool.post {} }.to raise_error(Shoryuken::Errors::RejectedExecutionError)
    end
  end

  describe 'idle threads' do
    before { stub_const("#{described_class}::IDLE_TIMEOUT", 0.1) }

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
