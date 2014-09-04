require 'spec_helper'

describe 'core_ext' do
  describe String do
    describe '#constantize' do
      class HelloWorld; end
      it 'returns a class from a string' do
        expect('HelloWorld'.constantize).to eq HelloWorld
      end
    end
  end
end
