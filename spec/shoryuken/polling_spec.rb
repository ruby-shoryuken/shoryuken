require 'spec_helper'
require 'shoryuken/polling'

describe Shoryuken::Polling do
  let(:queue1) { "shoryuken" }
  let(:queue2) { "uppercut" }
  let(:queues) { Array.new }

  describe Shoryuken::Polling::WeightedRoundRobin do
    subject { Shoryuken::Polling::WeightedRoundRobin.new(queues) }

    it "decreases weight" do
      # [shoryuken, 2]
      # [uppercut,  1]
      queues << queue1
      queues << queue1
      queues << queue2

      expect(subject).to eq [queue1, queue2]

      subject.pause(queue1)

      expect(subject).to eq [queue2]
    end

    it "increases weight" do
      # [shoryuken, 3]
      # [uppercut,  1]
      queues << queue1
      queues << queue1
      queues << queue1
      queues << queue2

      expect(subject).to eq [queue1, queue2]
      subject.pause(queue1)
      expect(subject).to eq [queue2]

      subject.messages_present(queue1)
      expect(subject).to eq [queue2, queue1]

      subject.messages_present(queue1)
      expect(subject).to eq [queue2, queue1, queue1]

      subject.messages_present(queue1)
      expect(subject).to eq [queue2, queue1, queue1, queue1]
    end

    it "cycles" do
      # [shoryuken, 1]
      # [uppercut,  1]
      queues << queue1
      queues << queue2

      popped = []

      (queues.size * 3).times do
        popped << subject.next_queue
      end

      expect(popped).to eq(queues * 3)
    end
  end
end
