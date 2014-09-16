require 'spec_helper'

describe 'Shoryuken::Worker' do

  describe '.shoryuken_options' do
    it 'registers the worker' do
      class UppercutWorker
        include Shoryuken::Worker

        shoryuken_options queue: 'uppercut'
      end

      expect(Shoryuken.workers['uppercut']).to eq UppercutWorker
    end

    it 'accepts a block as queue name' do
      $queue_prefix = 'production'

      class UppercutWorker
        include Shoryuken::Worker

        shoryuken_options queue: ->{ "#{$queue_prefix}_uppercut" }
      end

      expect(Shoryuken.workers['production_uppercut']).to eq UppercutWorker
    end
  end
end
