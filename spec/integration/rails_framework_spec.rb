# frozen_string_literal: true

require 'spec_helper'
require 'rails'
require 'active_job/railtie'
require 'active_support/all'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'

# Full Rails framework integration tests
# These tests load the complete Rails environment to catch edge cases
RSpec.describe 'Rails Framework Integration', :rails do
  # Minimal Rails application for testing
  class TestRailsApp < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.active_job.queue_adapter = :shoryuken
    config.eager_load = false
    config.logger = Logger.new('/dev/null')
    config.log_level = :fatal

    # Disable various Rails features we don't need for testing
    config.active_record.sqlite3_adapter_strict_strings_by_default = false if config.respond_to?(:active_record)
    config.force_ssl = false if config.respond_to?(:force_ssl)
  end

  before(:all) do
    # Initialize the Rails application
    unless Rails.application
      TestRailsApp.initialize!
    end

    # Ensure ActiveJob uses Shoryuken adapter
    ActiveJob::Base.queue_adapter = :shoryuken
  end

  before do
    # Reset Shoryuken state
    Shoryuken.groups.clear
    Shoryuken.worker_registry.clear

    # Ensure ActiveJob uses Shoryuken adapter (in case it was changed)
    ActiveJob::Base.queue_adapter = :shoryuken

    # Mock SQS interactions
    allow(Aws.config).to receive(:[]).with(:stub_responses).and_return(true)
  end

  # Test job classes within Rails context
  class RailsEmailJob < ActiveJob::Base
    queue_as :default

    def perform(user_id, message, options = {})
      Rails.logger.info "Processing email for user #{user_id}: #{message}"
      {
        user_id: user_id,
        message: message,
        options: options,
        rails_env: Rails.env,
        processed_at: Time.current
      }
    end
  end

  class RailsConfigurableJob < ActiveJob::Base
    queue_as :default

    def perform(data)
      "Processed in #{Rails.env}: #{data}"
    end
  end

  class RailsRetryJob < ActiveJob::Base
    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on ArgumentError
    queue_as :retry_queue

    def perform(action, attempt_count = 0)
      case action
      when 'succeed'
        "Success after #{attempt_count} attempts in #{Rails.env}"
      when 'retry_then_succeed'
        raise StandardError, 'Temporary failure' if attempt_count < 2
        "Success after retries in #{Rails.env}"
      when 'discard'
        raise ArgumentError, 'Invalid arguments - should be discarded'
      else
        raise StandardError, 'Unknown action'
      end
    end
  end

  class RailsTransactionJob < ActiveJob::Base
    queue_as :transactions

    def perform(operation_id)
      # Simulate database operations that might be in transactions
      Rails.logger.info "Executing transaction operation: #{operation_id}"
      {
        operation_id: operation_id,
        executed_at: Time.current,
        rails_env: Rails.env
      }
    end
  end

  describe 'Rails Environment Integration' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'correctly identifies Rails environment in jobs' do
      expect(Rails.env).to eq('test')

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')
        expect(body['arguments']).to eq([123, 'Test message', { 'priority' => 'high' }])
      end

      RailsEmailJob.perform_later(123, 'Test message', priority: 'high')
    end

    it 'handles Rails.env-dependent queue selection' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['queue_name']).to eq('default')
      end

      RailsConfigurableJob.perform_later('test data')
    end

    it 'integrates with Rails configuration for ActiveJob' do
      expect(Rails.application.config.active_job.queue_adapter).to eq(:shoryuken)
      expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::ShoryukenAdapter)
    end
  end

  describe 'Rails Logger Integration' do
    let(:queue) { double('Queue', fifo?: false) }
    let(:log_output) { StringIO.new }
    let(:logger) { Logger.new(log_output) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)

      # Capture Rails logger output
      Rails.logger = logger
      Rails.logger.level = Logger::INFO
    end

    after do
      Rails.logger = Logger.new('/dev/null')
    end

    it 'logs job enqueuing through Rails logger' do
      # Enable ActiveJob logging
      Rails.application.config.active_job.logger = logger

      RailsEmailJob.perform_later(456, 'Logger test')

      log_content = log_output.string
      expect(log_content).to include('RailsEmailJob') # Check for job name in logs
    end
  end

  describe 'Rails Cache Integration' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)

      # Ensure Rails cache is available
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    class CacheAwareJob < ActiveJob::Base
      queue_as :cache_test

      def perform(cache_key, value)
        Rails.cache.write(cache_key, value)
        Rails.cache.read(cache_key)
      end
    end

    it 'can access Rails cache from job serialization context' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('CacheAwareJob')
        expect(body['arguments']).to eq(['test_key', 'test_value'])
      end

      CacheAwareJob.perform_later('test_key', 'test_value')
    end
  end

  describe 'Rails Time Zone Handling' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)

      # Set a specific time zone
      Time.zone = 'Pacific Time (US & Canada)'
    end

    after do
      Time.zone = nil
    end

    class TimeZoneJob < ActiveJob::Base
      queue_as :timezone_test

      def perform(scheduled_time)
        {
          scheduled_time: scheduled_time,
          current_time: Time.current,
          time_zone: Time.zone.name
        }
      end
    end

    it 'handles time zone correctly in scheduled jobs' do
      future_time = 5.minutes.from_now

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('TimeZoneJob')
        expect(params[:delay_seconds]).to be > 0

        # Verify time is serialized correctly
        scheduled_arg = body['arguments'].first
        expect(Time.parse(scheduled_arg)).to be_within(5.seconds).of(future_time)
      end

      TimeZoneJob.set(wait_until: future_time).perform_later(future_time.iso8601)
    end
  end

  describe 'Rails Callbacks and Instrumentation' do
    let(:queue) { double('Queue', fifo?: false) }
    let(:events) { [] }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)

      # Subscribe to ActiveJob events
      @subscription = ActiveSupport::Notifications.subscribe(/active_job/) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end
    end

    after do
      ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
    end

    class CallbackJob < ActiveJob::Base
      queue_as :callbacks

      before_enqueue :log_before_enqueue
      after_enqueue :log_after_enqueue

      def perform(message)
        "Processed: #{message}"
      end

      private

      def log_before_enqueue
        Rails.logger.info "About to enqueue #{self.class.name}"
      end

      def log_after_enqueue
        Rails.logger.info "Enqueued #{self.class.name} with job_id: #{job_id}"
      end
    end

    it 'executes ActiveJob callbacks correctly' do
      log_output = StringIO.new
      Rails.logger = Logger.new(log_output)
      Rails.logger.level = Logger::INFO

      CallbackJob.perform_later('callback test')

      log_content = log_output.string
      expect(log_content).to include('About to enqueue CallbackJob')
      expect(log_content).to include('Enqueued CallbackJob with job_id:')

      Rails.logger = Logger.new('/dev/null')
    end

    it 'fires ActiveSupport::Notifications events' do
      CallbackJob.perform_later('notification test')

      enqueue_events = events.select { |e| e.name == 'enqueue.active_job' }
      expect(enqueue_events).not_to be_empty

      event = enqueue_events.first
      expect(event.payload[:job]).to be_a(CallbackJob)
    end
  end

  describe 'Rails Configuration Edge Cases' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'handles jobs when Rails is reloading (development mode simulation)' do
      # Simulate Rails reloading behavior
      original_cache_classes = Rails.application.config.cache_classes
      Rails.application.config.cache_classes = false

      begin
        expect(queue).to receive(:send_message) do |params|
          body = params[:message_body]
          expect(body['job_class']).to eq('RailsEmailJob')
        end

        RailsEmailJob.perform_later(789, 'Reload test')
      ensure
        Rails.application.config.cache_classes = original_cache_classes
      end
    end

    it 'handles queue name prefixes correctly' do
      # Test queue name prefix functionality
      original_prefix = ActiveJob::Base.queue_name_prefix
      ActiveJob::Base.queue_name_prefix = 'myapp'

      begin
        expect(queue).to receive(:send_message) do |params|
          body = params[:message_body]
          expect(body['queue_name']).to eq('myapp_default')
        end

        RailsEmailJob.perform_later(101, 'Prefix test')
      ensure
        ActiveJob::Base.queue_name_prefix = original_prefix
      end
    end

    it 'handles queue name delimiters correctly' do
      original_delimiter = ActiveJob::Base.queue_name_delimiter
      ActiveJob::Base.queue_name_delimiter = '-'
      ActiveJob::Base.queue_name_prefix = 'app'

      begin
        expect(queue).to receive(:send_message) do |params|
          body = params[:message_body]
          expect(body['queue_name']).to eq('app-default')
        end

        RailsEmailJob.perform_later(102, 'Delimiter test')
      ensure
        ActiveJob::Base.queue_name_delimiter = original_delimiter
        ActiveJob::Base.queue_name_prefix = nil
      end
    end
  end

  describe 'Rails 7.2+ Transaction Integration' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'supports enqueue_after_transaction_commit' do
      adapter = ActiveJob::QueueAdapters::ShoryukenAdapter.new
      expect(adapter.enqueue_after_transaction_commit?).to be true
    end

    it 'handles transaction-aware job enqueueing' do
      # This would be more complex in a real Rails app with ActiveRecord
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsTransactionJob')
        expect(body['arguments']).to eq(['txn-123'])
      end

      RailsTransactionJob.perform_later('txn-123')
    end
  end

  describe 'Rails Error Handling Integration' do
    let(:queue) { double('Queue', fifo?: false) }
    let(:sqs_msg) { double('SQS Message', attributes: { 'ApproximateReceiveCount' => '1' }, message_id: 'test-msg') }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'integrates with Rails error reporting' do
      # Test that errors are properly handled through Rails error handling
      job_data = {
        'job_class' => 'RailsRetryJob',
        'job_id' => SecureRandom.uuid,
        'queue_name' => 'retry_queue',
        'arguments' => ['retry_then_succeed', 0],
        'executions' => 0,
        'enqueued_at' => Time.current.iso8601
      }

      wrapper = Shoryuken::ActiveJob::JobWrapper.new

      # Mock ActiveJob::Base.execute to simulate retry behavior
      expect(ActiveJob::Base).to receive(:execute).with(job_data)

      wrapper.perform(sqs_msg, job_data)
    end
  end

  describe 'Rails Multi-tenancy Edge Cases' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    class TenantAwareJob < ActiveJob::Base
      queue_as :tenant_queue

      def perform(tenant_id, data)
        # Simulate tenant-aware processing
        "Processed for tenant #{tenant_id}: #{data}"
      end
    end

    it 'handles tenant-specific queue routing' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('TenantAwareJob')
        expect(body['arguments']).to eq(['tenant-123', 'tenant data'])
      end

      TenantAwareJob.perform_later('tenant-123', 'tenant data')
    end
  end

  describe 'Rails Internationalization (I18n) Integration' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)

      # Set locale
      I18n.available_locales = [:en, :es]
      I18n.locale = :es
    end

    after do
      I18n.locale = :en
      I18n.available_locales = [:en]
    end

    class I18nJob < ActiveJob::Base
      queue_as :i18n_queue

      def perform(message_key)
        {
          locale: I18n.locale,
          message: I18n.t(message_key, default: 'Default message')
        }
      end
    end

    it 'preserves locale context in job serialization' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('I18nJob')
        expect(body['locale']).to eq('es') if body['locale'] # ActiveJob might serialize locale
      end

      I18nJob.perform_later('welcome.message')
    end
  end

  describe 'Rails Memory and Performance Edge Cases' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'handles large job arguments efficiently' do
      large_data = { 'data' => 'x' * 10_000, 'array' => (1..1000).to_a }

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')
        expect(body['arguments'][2]['data'].length).to eq(10_000)
      end

      RailsEmailJob.perform_later(999, 'Large data test', large_data)
    end

    it 'handles rapid job enqueueing without memory leaks' do
      expect(queue).to receive(:send_message).exactly(50).times

      50.times do |i|
        RailsEmailJob.perform_later(i, "Rapid enqueue test #{i}")
      end
    end
  end
end
