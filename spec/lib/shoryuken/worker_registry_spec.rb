# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::WorkerRegistry do
  subject { described_class.new }

  describe '#batch_receive_messages?' do
    it 'raises NotImplementedError' do
      expect { subject.batch_receive_messages?('test-queue') }.to raise_error(NotImplementedError)
    end
  end

  describe '#clear' do
    it 'raises NotImplementedError' do
      expect { subject.clear }.to raise_error(NotImplementedError)
    end
  end

  describe '#fetch_worker' do
    it 'raises NotImplementedError' do
      queue = 'test-queue'
      message = double('message')
      expect { subject.fetch_worker(queue, message) }.to raise_error(NotImplementedError)
    end
  end

  describe '#queues' do
    it 'raises NotImplementedError' do
      expect { subject.queues }.to raise_error(NotImplementedError)
    end
  end

  describe '#register_worker' do
    it 'raises NotImplementedError' do
      queue = 'test-queue'
      worker_class = Class.new
      expect { subject.register_worker(queue, worker_class) }.to raise_error(NotImplementedError)
    end
  end

  describe '#workers' do
    it 'raises NotImplementedError' do
      expect { subject.workers('test-queue') }.to raise_error(NotImplementedError)
    end
  end

  context 'interface documentation' do
    it 'defines the required interface methods' do
      expect(subject).to respond_to(:batch_receive_messages?)
      expect(subject).to respond_to(:clear)
      expect(subject).to respond_to(:fetch_worker)
      expect(subject).to respond_to(:queues)
      expect(subject).to respond_to(:register_worker)
      expect(subject).to respond_to(:workers)
    end

    it 'is designed to be subclassed' do
      expect(described_class).to be < Object
      expect(described_class.ancestors).to include(described_class)
    end
  end
end