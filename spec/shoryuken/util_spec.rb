require 'spec_helper'

describe 'Shoryuken::Util' do
  class SuperUtil
    include Shoryuken::Util
  end

  subject { SuperUtil.new }

  describe '#constantize' do
    class HelloWorld; end

    it 'returns a class from a string' do
      expect(subject.constantize('HelloWorld')).to eq HelloWorld
    end
  end
end
