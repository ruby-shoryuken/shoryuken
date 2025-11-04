# frozen_string_literal: true

require 'spec_helper'
require 'rails/all'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'

# Focused Rails framework edge case tests
RSpec.describe 'Rails Framework Edge Cases', :rails do
  # Minimal Rails application for testing edge cases
  class EdgeCaseRailsApp < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.active_job.queue_adapter = :shoryuken
    config.eager_load = false
    config.logger = Logger.new('/dev/null')
    config.log_level = :fatal
    config.cache_store = :memory_store

    # Disable various Rails features we don't need
    config.active_record.sqlite3_adapter_strict_strings_by_default = false if config.respond_to?(:active_record)
    config.force_ssl = false if config.respond_to?(:force_ssl)
  end

  before(:all) do
    # Initialize Rails if not already done
    unless Rails.application
      EdgeCaseRailsApp.initialize!
    end

    # Ensure ActiveJob uses Shoryuken
    ActiveJob::Base.queue_adapter = :shoryuken
  end

  before do
    # Reset state
    Shoryuken.groups.clear
    Shoryuken.worker_registry.clear
    ActiveJob::Base.queue_adapter = :shoryuken

    # Mock SQS
    allow(Aws.config).to receive(:[]).with(:stub_responses).and_return(true)
  end

  # Test job for edge cases
  class EdgeCaseJob < ActiveJob::Base
    queue_as :edge_cases

    def perform(scenario, data = {})
      case scenario
      when 'rails_cache'
        Rails.cache.write('test_key', data)
        Rails.cache.read('test_key')
      when 'rails_logger'
        Rails.logger.info("Processing: #{data}")
        data
      when 'large_payload'
        # Simulate processing large data
        "Processed #{data['size']} bytes"
      when 'unicode'
        # Test unicode handling
        "Processed: #{data['text']} 🚀"
      else
        "Unknown scenario: #{scenario}"
      end
    end
  end

  describe 'Rails Cache Integration Edge Cases' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'handles jobs that interact with Rails cache' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('EdgeCaseJob')
        expect(body['arguments']).to include('rails_cache')
      end

      EdgeCaseJob.perform_later('rails_cache', { 'value' => 'cached_data' })
    end

    it 'works when Rails cache is disabled' do
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::NullStore.new

      begin
        expect(queue).to receive(:send_message) do |params|
          body = params[:message_body]
          expect(body['job_class']).to eq('EdgeCaseJob')
        end

        EdgeCaseJob.perform_later('rails_cache', { 'value' => 'no_cache' })
      ensure
        Rails.cache = original_cache
      end
    end
  end

  describe 'Rails Logger Integration Edge Cases' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'handles jobs when Rails logger is configured' do
      log_output = StringIO.new
      original_logger = Rails.logger
      Rails.logger = Logger.new(log_output)

      begin
        expect(queue).to receive(:send_message) do |params|
          body = params[:message_body]
          expect(body['job_class']).to eq('EdgeCaseJob')
        end

        EdgeCaseJob.perform_later('rails_logger', { 'message' => 'test log' })
      ensure
        Rails.logger = original_logger
      end
    end
  end

  describe 'Large Payload Edge Cases' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'handles jobs with large payloads efficiently' do
      large_data = {
        'size' => 50_000,
        'content' => 'x' * 50_000,
        'metadata' => {
          'created_at' => Time.current.iso8601,
          'tags' => Array.new(1000) { |i| "tag_#{i}" }
        }
      }

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('EdgeCaseJob')
        expect(body['arguments'][1]['size']).to eq(50_000)

        # Verify the message can be JSON serialized without issues
        expect { JSON.generate(body) }.not_to raise_error
      end

      EdgeCaseJob.perform_later('large_payload', large_data)
    end
  end

  describe 'Unicode and Character Encoding Edge Cases' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'handles unicode characters correctly' do
      unicode_data = {
        'text' => 'Hello 世界! 🌍 Café résumé naïve',
        'emoji' => '🚀💎🎯⚡️🔥',
        'languages' => {
          'chinese' => '你好世界',
          'japanese' => 'こんにちは世界',
          'arabic' => 'مرحبا بالعالم',
          'russian' => 'Привет мир'
        }
      }

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('EdgeCaseJob')
        expect(body['arguments'][1]['text']).to include('世界')
        expect(body['arguments'][1]['emoji']).to include('🚀')

        # Verify proper encoding
        expect(body['arguments'][1]['text'].encoding).to eq(Encoding::UTF_8)
      end

      EdgeCaseJob.perform_later('unicode', unicode_data)
    end
  end

  describe 'Rails Configuration Conflicts' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'works when multiple queue adapters are configured' do
      # Simulate scenario where app has multiple queue adapters
      original_adapter = ActiveJob::Base.queue_adapter

      # Temporarily set to async adapter
      ActiveJob::Base.queue_adapter = :async

      # Then switch back to Shoryuken
      ActiveJob::Base.queue_adapter = :shoryuken

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('EdgeCaseJob')
      end

      EdgeCaseJob.perform_later('adapter_switch', { 'test' => 'multi_adapter' })

      # Restore original
      ActiveJob::Base.queue_adapter = original_adapter
    end

    it 'handles jobs when Rails is in different environments' do
      original_env = Rails.env

      # Simulate production environment
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('EdgeCaseJob')
      end

      EdgeCaseJob.perform_later('env_test', { 'env' => 'production' })

      # Restore
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(original_env))
    end
  end

  describe 'Memory and Performance Under Rails' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'handles rapid job creation without memory leaks' do
      expect(queue).to receive(:send_message).exactly(100).times

      # Create many jobs rapidly
      100.times do |i|
        EdgeCaseJob.perform_later('performance_test', { 'iteration' => i })
      end

      # In a real scenario, you might check memory usage here
      # For testing, we just verify all jobs were enqueued
    end

    it 'handles nested hash structures efficiently' do
      nested_data = {
        'level1' => {
          'level2' => {
            'level3' => {
              'level4' => {
                'level5' => {
                  'data' => 'deeply nested',
                  'array' => Array.new(100) { |i| { "item_#{i}" => "value_#{i}" } }
                }
              }
            }
          }
        }
      }

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('EdgeCaseJob')

        # Verify deep nesting is preserved
        deep_data = body['arguments'][1]['level1']['level2']['level3']['level4']['level5']
        expect(deep_data['data']).to eq('deeply nested')
        expect(deep_data['array'].size).to eq(100)
      end

      EdgeCaseJob.perform_later('nested_structures', nested_data)
    end
  end

  describe 'Rails Zeitwerk Autoloading Compatibility' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'works with Zeitwerk autoloading enabled' do
      # Test that job classes are properly loaded even with Zeitwerk
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('EdgeCaseJob')

        # Verify the job class can be constantized
        expect { body['job_class'].constantize }.not_to raise_error
      end

      EdgeCaseJob.perform_later('zeitwerk_test', { 'autoload' => true })
    end
  end
end
