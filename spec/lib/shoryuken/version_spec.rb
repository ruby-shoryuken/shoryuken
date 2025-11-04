# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::VERSION do
  it 'has a version number' do
    expect(Shoryuken::VERSION).not_to be_nil
  end

  it 'follows semantic versioning format' do
    expect(Shoryuken::VERSION).to match(/^\d+\.\d+\.\d+/)
  end

  it 'is a string' do
    expect(Shoryuken::VERSION).to be_a(String)
  end
end