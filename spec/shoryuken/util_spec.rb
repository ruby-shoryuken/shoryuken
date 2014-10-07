require 'spec_helper'

describe 'Shoryuken::Util' do
  subject do
    Class.new do
      extend Shoryuken::Util
    end
  end

  describe '#unparse_queues' do
    it 'returns queues and weights' do
      queues = %w[queue1 queue1 queue2 queue3 queue4 queue4 queue4]

      expect(subject.unparse_queues(queues)).to eq([['queue1', 2], ['queue2', 1], ['queue3', 1], ['queue4', 3]])
    end
  end
end
