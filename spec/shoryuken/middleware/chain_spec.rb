require 'spec_helper'

RSpec.describe Shoryuken::Middleware::Chain do
  class CustomMiddleware
    def initialize(name, recorder)
      @name     = name
      @recorder = recorder
    end

    def call(*_args)
      @recorder << [@name, 'before']
      yield
      @recorder << [@name, 'after']
    end
  end

  class CustomMiddlewareB < CustomMiddleware; end

  it 'supports custom middleware' do
    subject.add CustomMiddleware, 1, []

    expect(CustomMiddleware).to eq subject.entries.last.klass
  end

  it 'can add middleware to the front of chain' do
    subject.prepend CustomMiddleware, 1, []

    expect([CustomMiddleware]).to eq subject.entries.map(&:klass)

    subject.prepend CustomMiddlewareB, 1, []

    expect([CustomMiddlewareB, CustomMiddleware]).to eq subject.entries.map(&:klass)
  end

  it 'invokes a middleware' do
    recorder = []
    subject.add CustomMiddleware, 'custom', recorder

    final_action = nil
    subject.invoke { final_action = true }
    expect(final_action).to eq true
    expect(recorder).to eq [%w[custom before], %w[custom after]]
  end

  class NonYieldingMiddleware
    def call(*args); end
  end

  it 'allows middleware to abruptly stop processing rest of chain' do
    recorder = []
    subject.add NonYieldingMiddleware
    subject.add CustomMiddleware, 'custom', recorder

    final_action = nil
    subject.invoke { final_action = true }
    expect(final_action).to eq nil
    expect(recorder).to eq []
  end
end
