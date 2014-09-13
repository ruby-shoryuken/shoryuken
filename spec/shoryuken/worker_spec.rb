require 'spec_helper'

describe 'Shoryuken::Worker' do
  class YoWorker
    include Shoryuken::Worker

    shoryuken_options queue: 'yo'
  end

  describe '.shoryuken_options' do
    it 'registers the worker' do
      expect(Shoryuken.workers['yo']).to eq YoWorker
    end
  end
end
