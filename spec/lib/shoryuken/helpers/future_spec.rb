# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Helpers::Future do
  subject(:future) { described_class.new }

  it 'is not resolved before it runs' do
    expect(future).not_to be_resolved
    expect(future.wait(0.05)).to be false
    expect(future.value(0)).to be_nil
  end

  describe '#execute' do
    it 'resolves with the block result' do
      future.execute { 42 }

      expect(future).to be_resolved
      expect(future).to be_fulfilled
      expect(future).not_to be_rejected
      expect(future.value).to eq(42)
      expect(future.reason).to be_nil
    end

    it 'resolves with the error the block raises' do
      error = RuntimeError.new('send failed')

      future.execute { raise error }

      expect(future).to be_rejected
      expect(future).not_to be_fulfilled
      expect(future.value).to be_nil
      expect(future.reason).to be(error)
    end
  end

  describe '#wait' do
    it 'wakes up when another thread resolves the future' do
      Thread.new do
        sleep 0.1
        future.execute { :done }
      end

      expect(future.wait(5)).to be true
      expect(future.value).to eq(:done)
    end
  end
end
