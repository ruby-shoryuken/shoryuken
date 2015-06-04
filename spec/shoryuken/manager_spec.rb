require 'spec_helper'
require 'shoryuken/manager'

RSpec.describe Shoryuken::Manager do
  subject do
    condvar = double(:condvar)
    allow(condvar).to receive(:signal).and_return(nil)
    Shoryuken::Manager.new(condvar)
  end

  describe 'Invalid concurrency setting' do
    it 'raises ArgumentError if concurrency is not positive number' do
      Shoryuken.options[:concurrency] = -1
      expect { Shoryuken::Manager.new(nil) }
        .to raise_error(ArgumentError, 'Concurrency value -1 is invalid, it needs to be a positive number')
    end

  end

  describe 'Auto Scaling' do
    it 'decreases weight' do
      queue1 = 'shoryuken'
      queue2 = 'uppercut'

      Shoryuken.queues.clear
      # [shoryuken, 2]
      # [uppercut,  1]
      Shoryuken.queues << queue1
      Shoryuken.queues << queue1
      Shoryuken.queues << queue2

      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue1, queue2]

      subject.queue_empty(queue1)

      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue2]
    end

    it 'increases weight' do
      queue1 = 'shoryuken'
      queue2 = 'uppercut'

      Shoryuken.queues.clear
      # [shoryuken, 3]
      # [uppercut,  1]
      Shoryuken.queues << queue1
      Shoryuken.queues << queue1
      Shoryuken.queues << queue1
      Shoryuken.queues << queue2

      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue1, queue2]
      subject.queue_empty(queue1)
      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue2]

      subject.messages_present(queue1)
      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue2, queue1]

      subject.messages_present(queue1)
      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue2, queue1, queue1]

      subject.messages_present(queue1)
      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue2, queue1, queue1, queue1]
    end

    it 'adds queue back' do
      queue1 = 'shoryuken'
      queue2 = 'uppercut'

      Shoryuken.queues.clear
      # [shoryuken, 2]
      # [uppercut,  1]
      Shoryuken.queues << queue1
      Shoryuken.queues << queue1
      Shoryuken.queues << queue2

      Shoryuken.options[:delay] = 0.1

      fetcher = double('Fetcher').as_null_object
      subject.fetcher = fetcher

      subject.queue_empty(queue1)
      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue2]

      sleep 0.5

      expect(subject.instance_variable_get('@polling_strategy')).to eq [queue2, queue1]
    end
  end

  describe '#next_queue' do
    it 'returns queues' do
      queue1 = 'shoryuken'
      queue2 = 'uppercut'

      Shoryuken.queues.clear

      Shoryuken.register_worker queue1, TestWorker
      Shoryuken.register_worker queue2, TestWorker

      Shoryuken.queues << queue1
      Shoryuken.queues << queue2

      expect(subject.send :next_queue).to eq queue1
      expect(subject.send :next_queue).to eq queue2
    end

    it 'skips when no worker' do
      queue1 = 'shoryuken'
      queue2 = 'uppercut'

      Shoryuken.queues.clear

      Shoryuken.register_worker queue2, TestWorker

      Shoryuken.queues << queue1
      Shoryuken.queues << queue2

      expect(subject.send :next_queue).to eq queue2
      expect(subject.send :next_queue).to eq queue2
    end
  end
end
