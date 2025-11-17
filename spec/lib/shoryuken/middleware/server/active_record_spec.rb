# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Middleware::Server::ActiveRecord do
  subject { described_class.new }

  # Mock ActiveRecord to avoid requiring the actual gem in tests
  before do
    # Create mock ActiveRecord module
    active_record_module = Module.new

    # Create mock Base class with simplified methods
    active_record_base = Class.new do
      @connection_handler = nil

      def self.clear_active_connections!
        # Mock implementation for Rails < 7.1
      end

      def self.connection_handler
        @connection_handler ||= Object.new.tap do |handler|
          def handler.clear_active_connections!(_pool_key)
            # Mock implementation for Rails 7.1+
          end
        end
      end
    end

    active_record_module.const_set('Base', active_record_base)
    stub_const('ActiveRecord', active_record_module)

    # Mock version checking - start with a simple approach
    def active_record_module.version
      @version ||= Object.new.tap do |v|
        def v.>=(other)
          # For our tests, we'll control this with instance variables
          @is_rails_71_or_higher ||= false
        end

        def v.rails_71_or_higher!
          @is_rails_71_or_higher = true
        end

        def v.rails_70!
          @is_rails_71_or_higher = false
        end
      end
    end

    # Mock Gem::Version
    unless defined?(Gem::Version)
      gem_module = Module.new
      gem_version_class = Class.new do
        def initialize(_version)
          # Simple mock
        end
      end
      gem_module.const_set('Version', gem_version_class)
      stub_const('Gem', gem_module)
    end
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

    context 'when ActiveRecord version is 7.1 or higher' do
      before do
        # Mock Rails 7.1+ behavior
        allow(ActiveRecord).to receive(:version).and_return(double('>=' => true))
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
    end

    context 'when ActiveRecord version is lower than 7.1' do
      before do
        # Mock Rails < 7.1 behavior
        allow(ActiveRecord).to receive(:version).and_return(double('>=' => false))
      end

      it 'calls clear_active_connections! directly on ActiveRecord::Base' do
        expect(ActiveRecord::Base).to receive(:clear_active_connections!)

        subject.call { 'test' }
      end

      it 'clears connections even when an exception is raised' do
        expect(ActiveRecord::Base).to receive(:clear_active_connections!)

        expect do
          subject.call { raise StandardError, 'test error' }
        end.to raise_error(StandardError, 'test error')
      end
    end

    it 'works with middleware arguments (ignores them)' do
      allow(ActiveRecord).to receive(:version).and_return(double('>=' => false))
      expect(ActiveRecord::Base).to receive(:clear_active_connections!)

      worker = double('worker')
      message = double('message')

      result = subject.call(worker, message) { 'middleware_result' }
      expect(result).to eq('middleware_result')
    end
  end
end