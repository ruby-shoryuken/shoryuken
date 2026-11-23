# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Middleware::Server::ActiveRecord do
  subject { described_class.new }

  # Mock ActiveRecord to avoid requiring the actual gem in tests
  before do
    active_record_module = Module.new

    active_record_base = Class.new do
      @connection_handler = nil

      def self.connection_handler
        @connection_handler ||= Object.new.tap do |handler|
          def handler.clear_active_connections!(_pool_key)
            # Mock implementation
          end
        end
      end
    end

    active_record_module.const_set('Base', active_record_base)
    stub_const('ActiveRecord', active_record_module)
  end

  describe '#call' do
    it 'yields to the block' do
      block_called = false
      subject.call do
        block_called = true
      end
      expect(block_called).to be true
    end

    it 'returns the value from the block' do
      result = subject.call { 'block_result' }
      expect(result).to eq('block_result')
    end

    it 'calls clear_active_connections! on connection_handler with :all parameter' do
      connection_handler = ActiveRecord::Base.connection_handler
      expect(connection_handler).to receive(:clear_active_connections!).with(:all)

      subject.call { 'test' }
    end

    it 'clears connections even when an exception is raised' do
      connection_handler = ActiveRecord::Base.connection_handler
      expect(connection_handler).to receive(:clear_active_connections!).with(:all)

      expect do
        subject.call { raise StandardError, 'test error' }
      end.to raise_error(StandardError, 'test error')
    end

    it 'works with middleware arguments (ignores them)' do
      expect(ActiveRecord::Base.connection_handler).to receive(:clear_active_connections!).with(:all)

      worker = double('worker')
      message = double('message')

      result = subject.call(worker, message) { 'middleware_result' }
      expect(result).to eq('middleware_result')
    end
  end
end
