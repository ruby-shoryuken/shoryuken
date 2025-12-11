# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Logging do
  describe Shoryuken::Logging::Base do
    let(:formatter) { described_class.new }

    describe '#tid' do
      it 'returns a string representing the thread ID' do
        expect(formatter.tid).to be_a(String)
      end

      it 'returns the same value for the same thread' do
        tid1 = formatter.tid
        tid2 = formatter.tid
        expect(tid1).to eq(tid2)
      end

      it 'caches the thread ID in thread-local storage' do
        tid = formatter.tid
        expect(Thread.current['shoryuken_tid']).to eq(tid)
      end
    end

    describe '#context' do
      after do
        Shoryuken::Logging.context_storage[:shoryuken_context] = nil
      end

      it 'returns empty string when no context is set' do
        Shoryuken::Logging.context_storage[:shoryuken_context] = nil
        expect(formatter.context).to eq('')
      end

      it 'returns formatted context when context is set' do
        Shoryuken::Logging.context_storage[:shoryuken_context] = 'test_context'
        expect(formatter.context).to eq(' test_context')
      end
    end
  end

  describe Shoryuken::Logging::Pretty do
    let(:formatter) { described_class.new }
    let(:time) { Time.new(2023, 8, 15, 10, 30, 45, '+00:00') }

    describe '#call' do
      after do
        Shoryuken::Logging.context_storage[:shoryuken_context] = nil
      end

      it 'formats log messages with timestamp' do
        allow(formatter).to receive(:tid).and_return('abc123')
        Shoryuken::Logging.context_storage[:shoryuken_context] = nil

        result = formatter.call('INFO', time, 'program', 'test message')
        expect(result).to eq("2023-08-15T10:30:45Z #{Process.pid} TID-abc123 INFO: test message\n")
      end

      it 'includes context when present' do
        allow(formatter).to receive(:tid).and_return('abc123')
        Shoryuken::Logging.context_storage[:shoryuken_context] = 'worker-1'

        result = formatter.call('ERROR', time, 'program', 'error message')
        expect(result).to eq("2023-08-15T10:30:45Z #{Process.pid} TID-abc123 worker-1 ERROR: error message\n")
      end
    end
  end

  describe Shoryuken::Logging::WithoutTimestamp do
    let(:formatter) { described_class.new }

    describe '#call' do
      after do
        Shoryuken::Logging.context_storage[:shoryuken_context] = nil
      end

      it 'formats log messages without timestamp' do
        allow(formatter).to receive(:tid).and_return('xyz789')
        Shoryuken::Logging.context_storage[:shoryuken_context] = nil

        result = formatter.call('DEBUG', Time.now, 'program', 'debug message')
        expect(result).to eq("pid=#{Process.pid} tid=xyz789 DEBUG: debug message\n")
      end

      it 'includes context when present' do
        allow(formatter).to receive(:tid).and_return('xyz789')
        Shoryuken::Logging.context_storage[:shoryuken_context] = 'queue-processor'

        result = formatter.call('WARN', Time.now, 'program', 'warning message')
        expect(result).to eq("pid=#{Process.pid} tid=xyz789 queue-processor WARN: warning message\n")
      end
    end
  end

  describe '.with_context' do
    after do
      described_class.context_storage[:shoryuken_context] = nil
    end

    it 'sets context for the duration of the block' do
      described_class.with_context('test_context') do
        expect(described_class.current_context).to eq('test_context')
      end
    end

    it 'clears context after the block completes' do
      described_class.with_context('test_context') do
        # context is set
      end
      expect(described_class.current_context).to be_nil
    end

    it 'clears context even when an exception is raised' do
      expect do
        described_class.with_context('test_context') do
          raise StandardError, 'test error'
        end
      end.to raise_error(StandardError, 'test error')

      expect(described_class.current_context).to be_nil
    end

    it 'returns the value of the block' do
      result = described_class.with_context('test_context') do
        'block_result'
      end
      expect(result).to eq('block_result')
    end

    it 'preserves outer context in nested calls' do
      described_class.with_context('outer') do
        expect(described_class.current_context).to eq('outer')

        described_class.with_context('inner') do
          expect(described_class.current_context).to eq('inner')
        end

        expect(described_class.current_context).to eq('outer')
      end
      expect(described_class.current_context).to be_nil
    end

    it 'restores outer context even when inner block raises' do
      described_class.with_context('outer') do
        expect do
          described_class.with_context('inner') do
            raise StandardError, 'inner error'
          end
        end.to raise_error(StandardError, 'inner error')

        expect(described_class.current_context).to eq('outer')
      end
    end
  end

  describe '.current_context' do
    after do
      described_class.context_storage[:shoryuken_context] = nil
    end

    it 'returns nil when no context is set' do
      expect(described_class.current_context).to be_nil
    end

    it 'returns the current context value' do
      described_class.context_storage[:shoryuken_context] = 'test_value'
      expect(described_class.current_context).to eq('test_value')
    end
  end

  describe '.context_storage' do
    it 'returns Fiber on Ruby 3.2+' do
      if Fiber.respond_to?(:[])
        expect(described_class.context_storage).to eq(Fiber)
      else
        expect(described_class.context_storage).to eq(Thread.current)
      end
    end
  end

  describe '.initialize_logger' do
    it 'creates a new Logger instance' do
      logger = described_class.initialize_logger
      expect(logger).to be_a(Logger)
    end

    it 'sets default log level to INFO' do
      logger = described_class.initialize_logger
      expect(logger.level).to eq(Logger::INFO)
    end

    it 'uses Pretty formatter by default' do
      logger = described_class.initialize_logger
      expect(logger.formatter).to be_a(Shoryuken::Logging::Pretty)
    end

    it 'accepts custom log target' do
      log_target = StringIO.new
      logger = described_class.initialize_logger(log_target)
      expect(logger.instance_variable_get(:@logdev).dev).to eq(log_target)
    end
  end

  describe '.logger' do
    after do
      # Reset the instance variable to avoid affecting other tests
      described_class.instance_variable_set(:@logger, nil)
    end

    it 'returns a logger instance' do
      expect(described_class.logger).to be_a(Logger)
    end

    it 'memoizes the logger instance' do
      logger1 = described_class.logger
      logger2 = described_class.logger
      expect(logger1).to be(logger2)
    end

    it 'initializes logger if not already set' do
      expect(described_class).to receive(:initialize_logger).and_call_original
      described_class.logger
    end
  end

  describe '.logger=' do
    after do
      # Reset the instance variable to avoid affecting other tests
      described_class.instance_variable_set(:@logger, nil)
    end

    it 'sets the logger instance' do
      custom_logger = Logger.new('/dev/null')
      described_class.logger = custom_logger
      expect(described_class.logger).to be(custom_logger)
    end

    it 'sets null logger when passed nil' do
      described_class.logger = nil
      logger = described_class.logger
      # The logger should be configured to output to /dev/null
      expect(logger).to be_a(Logger)
    end
  end
end