require 'spec_helper'

describe Shoryuken::Middleware::Chain do
  class CustomMiddleware
    def initialize(name, recorder)
      @name     = name
      @recorder = recorder
    end

    def call(*args)
      @recorder << [@name, 'before']
      yield
      @recorder << [@name, 'after']
    end
  end

  it 'supports custom middleware' do
    subject.add CustomMiddleware, 1, []

    expect(CustomMiddleware).to eq subject.entries.last.klass
  end

  it 'invokes a middleware' do
    recorder = []
    subject.add CustomMiddleware, 'Pablo', recorder

    final_action = nil
    subject.invoke { final_action = true }
    expect(final_action).to eq true
    expect(recorder).to eq [%w[Pablo before], %w[Pablo after]]
  end

  class NonYieldingMiddleware
    def call(*args); end
  end

  it 'allows middleware to abruptly stop processing rest of chain' do
    recorder = []
    subject.add NonYieldingMiddleware
    subject.add CustomMiddleware, 'Pablo', recorder

    final_action = nil
    subject.invoke { final_action = true }
    expect(final_action).to eq nil
    expect(recorder).to eq []
  end

  class DeprecatedMiddleware
    def call(worker_instance, queue, sqs_msg)
      @@success = true
    end

    def self.success?
      !!@@success
    end
  end

  it 'patches deprecated middleware' do
    subject.clear

    expect(Shoryuken.logger).to receive(:warn).with("[DEPRECATION] DeprecatedMiddleware#call(worker_instance, queue, sqs_msg) is deprecated. Please use DeprecatedMiddleware#call(worker_instance, queue, sqs_msg, body)")

    subject.add DeprecatedMiddleware

    subject.invoke TestWorker, 'test', double('SQS msg', body: 'test'), 'test'

    expect(DeprecatedMiddleware.success?).to eq true
  end
end
