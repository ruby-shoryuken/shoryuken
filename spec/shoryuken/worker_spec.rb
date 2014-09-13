require 'spec_helper'

describe 'Shoryuken::Worker' do
  class UppercutWorker
    include Shoryuken::Worker

    shoryuken_options queue: 'uppercut'
  end

  describe '.shoryuken_options' do
    it 'registers the worker' do
      expect(Shoryuken.workers['uppercut']).to eq UppercutWorker
    end
  end
end
