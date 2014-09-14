require 'spec_helper'

describe Shoryuken::Manager do
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

      expect(subject.instance_variable_get('@queues')).to eq [queue1, queue1, queue2]

      subject.work_not_found!(queue1)

      expect(subject.instance_variable_get('@queues')).to eq [queue1, queue2]

      subject.work_not_found!(queue1)

      expect(subject.instance_variable_get('@queues')).to eq [queue1, queue2]
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

      expect(subject.instance_variable_get('@queues')).to eq [queue1, queue1, queue1, queue2]
      3.times { subject.work_not_found!(queue1) }
      expect(subject.instance_variable_get('@queues')).to eq [queue1, queue2]

      subject.work_found!(queue1)
      expect(subject.instance_variable_get('@queues')).to eq [queue1, queue2, queue1]

      subject.work_found!(queue1)
      expect(subject.instance_variable_get('@queues')).to eq [queue1, queue2, queue1, queue1]
    end
  end
end
