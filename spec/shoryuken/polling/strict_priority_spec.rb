require 'spec_helper'

RSpec.describe Shoryuken::Polling::StrictPriority do
  let(:queue1) { 'shoryuken' }
  let(:queue2) { 'uppercut' }
  let(:queue3) { 'other' }
  let(:queues) { [] }
  subject { Shoryuken::Polling::StrictPriority.new(queues) }

  describe '#next_queue' do
    it 'cycles when declared desc' do
      # [shoryuken, 2]
      # [uppercut,  1]
      queues << queue1
      queues << queue1
      queues << queue2

      expect(subject.next_queue).to eq(queue1)
      expect(subject.next_queue).to eq(queue2)
      expect(subject.next_queue).to eq(queue1)
      expect(subject.next_queue).to eq(queue2)
    end

    it 'cycles when declared asc' do
      # [uppercut,  1]
      # [shoryuken, 2]
      queues << queue2
      queues << queue1
      queues << queue1

      expect(subject.next_queue).to eq(queue1)
      expect(subject.next_queue).to eq(queue2)
      expect(subject.next_queue).to eq(queue1)
      expect(subject.next_queue).to eq(queue2)
    end

    it 'returns nil if there are no active queues' do
      expect(subject.next_queue).to eq(nil)
    end

    it 'unpauses queues whose pause is expired' do
      # [shoryuken, 3]
      # [uppercut,  2]
      # [other,     1]
      queues << queue1
      queues << queue1
      queues << queue1
      queues << queue2
      queues << queue2
      queues << queue3

      allow(subject).to receive(:delay).and_return(10)

      now = Time.now
      allow(Time).to receive(:now).and_return(now)

      # pause the second queue, see it loop between 1 and 3
      subject.messages_found(queue2, 0)
      expect(subject.next_queue).to eq(queue1)
      expect(subject.next_queue).to eq(queue3)
      expect(subject.next_queue).to eq(queue1)

      now += 5
      allow(Time).to receive(:now).and_return(now)

      # pause the first queue, see it repeat 3
      subject.messages_found(queue1, 0)
      expect(subject.next_queue).to eq(queue3)
      expect(subject.next_queue).to eq(queue3)

      # pause the third queue, see it have nothing
      subject.messages_found(queue3, 0)
      expect(subject.next_queue).to eq(nil)

      # unpause queue 2
      now += 6
      allow(Time).to receive(:now).and_return(now)
      expect(subject.next_queue).to eq(queue2)

      # unpause queues 1 and 3
      now += 6
      allow(Time).to receive(:now).and_return(now)
      expect(subject.next_queue).to eq(queue1)
      expect(subject.next_queue).to eq(queue2)
      expect(subject.next_queue).to eq(queue3)
    end
  end

  describe '#messages_found' do
    it 'pauses a queue if there are no messages found' do
      # [shoryuken, 2]
      # [uppercut,  1]
      queues << queue1
      queues << queue1
      queues << queue2

      expect(subject.active_queues).to eq([[queue1, 2], [queue2, 1]])
      expect(subject).to receive(:pause).with(queue1).and_call_original
      subject.messages_found(queue1, 0)
      expect(subject.active_queues).to eq([[queue2, 1]])
    end

    it 'continues to queue the highest priority queue if messages are found' do
      # [shoryuken, 3]
      # [uppercut,  2]
      # [other,     1]
      queues << queue1
      queues << queue1
      queues << queue1
      queues << queue2
      queues << queue2
      queues << queue3

      expect(subject.next_queue).to eq(queue1)
      subject.messages_found(queue1, 1)
      expect(subject.next_queue).to eq(queue1)
      subject.messages_found(queue1, 1)
      expect(subject.next_queue).to eq(queue1)
    end

    it 'resets the priorities if messages are found part way' do
      # [shoryuken, 3]
      # [uppercut,  2]
      # [other,     1]
      queues << queue1
      queues << queue1
      queues << queue1
      queues << queue2
      queues << queue2
      queues << queue3

      expect(subject.next_queue).to eq(queue1)
      expect(subject.next_queue).to eq(queue2)
      subject.messages_found(queue2, 1)
      expect(subject.next_queue).to eq(queue1)
      expect(subject.next_queue).to eq(queue2)
      expect(subject.next_queue).to eq(queue3)
    end
  end
end
