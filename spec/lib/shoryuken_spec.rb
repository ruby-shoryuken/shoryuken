# frozen_string_literal: true

RSpec.describe Shoryuken do
  describe '.healthy?' do
    before do
      allow(Shoryuken::Runner).to receive(:instance).and_return(double(:instance, healthy?: :some_result))
    end

    it 'delegates to the runner instance' do
      expect(described_class.healthy?).to eq(:some_result)
    end
  end
end
