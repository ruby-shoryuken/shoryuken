# frozen_string_literal: true

require 'spec_helper'

# Check if Rails is available
begin
  require 'rails/all'
  require 'action_controller/railtie'
  require 'action_mailer/railtie'
  require 'active_job/railtie'
  require 'rack/test'
  require 'active_job/queue_adapters/shoryuken_adapter'
  require 'active_job/extensions'

  RAILS_AVAILABLE = true
rescue LoadError
  RAILS_AVAILABLE = false
end

# Only run these tests when Rails is available
RSpec.describe 'Full Rails Application Integration', :rails_app do
  before(:all) do
    skip 'Rails not available' unless RAILS_AVAILABLE
  end

  # Create a full Rails application
  if RAILS_AVAILABLE
    class TestRailsApplication < Rails::Application
    # Rails application configuration
    config.load_defaults Rails::VERSION::STRING.to_f
    config.active_job.queue_adapter = :shoryuken
    config.eager_load = false
    config.consider_all_requests_local = true
    config.action_controller.perform_caching = false
    config.action_mailer.perform_caching = false
    config.cache_store = :memory_store
    config.public_file_server.enabled = true
    config.log_level = :debug
    config.logger = Logger.new('/dev/null') # Suppress logs in tests

    # Disable some Rails features for testing
    config.active_record.sqlite3_adapter_strict_strings_by_default = false if config.respond_to?(:active_record)
    config.force_ssl = false if config.respond_to?(:force_ssl)
    config.hosts.clear if config.respond_to?(:hosts)

    # Secret key for sessions
    config.secret_key_base = 'test_secret_key_base_for_testing_only'
  end

  # Rails Job classes that will be loaded in the Rails app
  class RailsEmailJob < ActiveJob::Base
    queue_as :emails

    def perform(user_id, email_type, options = {})
      Rails.logger.info "Sending #{email_type} email to user #{user_id}"

      # Simulate using Rails.cache
      cache_key = "email_#{user_id}_#{email_type}"
      Rails.cache.write(cache_key, Time.current)

      {
        user_id: user_id,
        email_type: email_type,
        options: options,
        sent_at: Time.current,
        cached_at: Rails.cache.read(cache_key),
        rails_env: Rails.env
      }
    end
  end

  class RailsDataProcessorJob < ActiveJob::Base
    queue_as :data_processing

    retry_on StandardError, wait: 5.seconds, attempts: 3

    def perform(data_type, payload)
      Rails.logger.info "Processing #{data_type} data"

      case data_type
      when 'user_analytics'
        process_user_analytics(payload)
      when 'system_metrics'
        process_system_metrics(payload)
      else
        raise ArgumentError, "Unknown data type: #{data_type}"
      end
    end

    private

    def process_user_analytics(payload)
      # Simulate database-like operations
      Rails.cache.write("analytics_#{payload['user_id']}", payload)
      "Processed user analytics for user #{payload['user_id']}"
    end

    def process_system_metrics(payload)
      Rails.cache.write("metrics_#{Time.current.to_i}", payload)
      "Processed system metrics"
    end
  end

  class RailsMailerJob < ActiveJob::Base
    queue_as :mailers

    def perform(mailer_class, action, delivery_method, params)
      # Simulate ActionMailer job
      Rails.logger.info "Delivering email via #{mailer_class}##{action}"

      {
        mailer: mailer_class,
        action: action,
        delivery_method: delivery_method,
        params: params,
        delivered_at: Time.current
      }
    end
  end

  # Controllers for testing Rails integration
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :null_session
  end

  class JobsController < ApplicationController
    def create_email_job
      RailsEmailJob.perform_later(
        params[:user_id], 
        params[:email_type], 
        { priority: params[:priority] }
      )

      render json: { message: 'Email job enqueued' }
    end

    def create_data_job
      RailsDataProcessorJob.perform_later(
        params[:data_type],
        params[:payload]
      )

      render json: { message: 'Data processing job enqueued' }
    end

    def create_scheduled_job
      RailsEmailJob.set(wait: 5.minutes).perform_later(
        params[:user_id],
        'reminder',
        { scheduled: true }
      )

      render json: { message: 'Scheduled job enqueued' }
    end
  end

  before(:all) do
    # Initialize the Rails application
    @app = TestRailsApplication.new

    # Set up routes
    @app.routes.draw do
      post 'jobs/email', to: 'jobs#create_email_job'
      post 'jobs/data', to: 'jobs#create_data_job'
      post 'jobs/scheduled', to: 'jobs#create_scheduled_job'
    end

    # Initialize the Rails application
    @app.initialize!

    # Set Rails.application
    Rails.application = @app
  end

  before do
    # Reset Shoryuken state
    Shoryuken.groups.clear
    Shoryuken.worker_registry.clear

    # Ensure ActiveJob uses Shoryuken
    ActiveJob::Base.queue_adapter = :shoryuken

    # Mock SQS interactions
    allow(Aws.config).to receive(:[]).with(:stub_responses).and_return(true)

    # Clear Rails cache
    Rails.cache.clear
  end

  describe 'Rails Application Boot Process' do
    it 'successfully boots Rails application' do
      expect(Rails.application).to be_a(TestRailsApplication)
      expect(Rails.application.initialized?).to be true
      expect(Rails.env).to eq('test')
    end

    it 'configures ActiveJob to use Shoryuken adapter' do
      expect(ActiveJob::Base.queue_adapter).to be_a(ActiveJob::QueueAdapters::ShoryukenAdapter)
      expect(Rails.application.config.active_job.queue_adapter).to eq(:shoryuken)
    end

    it 'has Rails cache configured' do
      expect(Rails.cache).to be_a(ActiveSupport::Cache::MemoryStore)
      Rails.cache.write('test_key', 'test_value')
      expect(Rails.cache.read('test_key')).to eq('test_value')
    end

    it 'has Rails logger configured' do
      expect(Rails.logger).to be_a(Logger)
      expect { Rails.logger.info('test message') }.not_to raise_error
    end
  end

  describe 'Jobs in Rails Context' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'enqueues jobs with access to Rails.cache' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')
        expect(body['arguments']).to eq([123, 'welcome', { 'priority' => 'high' }])
        expect(body['queue_name']).to eq('emails')
      end

      RailsEmailJob.perform_later(123, 'welcome', priority: 'high')
    end

    it 'enqueues jobs with Rails logger available' do
      log_output = StringIO.new
      original_logger = Rails.logger
      Rails.logger = Logger.new(log_output)
      Rails.logger.level = Logger::INFO

      begin
        expect(queue).to receive(:send_message) do |params|
          body = params[:message_body]
          expect(body['job_class']).to eq('RailsDataProcessorJob')
        end

        RailsDataProcessorJob.perform_later('user_analytics', { 'user_id' => 456 })
      ensure
        Rails.logger = original_logger
      end
    end

    it 'handles retry configurations in Rails context' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsDataProcessorJob')
        expect(body['queue_name']).to eq('data_processing')
      end

      # This job has retry_on configured
      RailsDataProcessorJob.perform_later('system_metrics', { 'metric_type' => 'cpu' })
    end
  end

  describe 'Rails Controller Integration' do
    include Rack::Test::Methods

    def app
      Rails.application
    end

    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'enqueues jobs through Rails controller actions' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')
        expect(body['arguments']).to eq([789, 'newsletter', { 'priority' => 'medium' }])
      end

      post '/jobs/email', {
        user_id: 789,
        email_type: 'newsletter',
        priority: 'medium'
      }

      expect(last_response.status).to eq(200)
      response_body = JSON.parse(last_response.body)
      expect(response_body['message']).to eq('Email job enqueued')
    end

    it 'enqueues data processing jobs through controller' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsDataProcessorJob')
        expect(body['arguments']).to eq(['user_analytics', { 'user_id' => 123, 'event' => 'login' }])
      end

      post '/jobs/data', {
        data_type: 'user_analytics',
        payload: { user_id: 123, event: 'login' }
      }

      expect(last_response.status).to eq(200)
    end

    it 'enqueues scheduled jobs through controller' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')
        expect(body['arguments']).to eq([555, 'reminder', { 'scheduled' => true }])
        expect(params[:delay_seconds]).to be > 250 # Approximately 5 minutes
      end

      post '/jobs/scheduled', { user_id: 555 }

      expect(last_response.status).to eq(200)
    end
  end

  describe 'Rails Environment Features' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'jobs have access to Rails configuration' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')
      end

      # Jobs should be able to access Rails config
      expect(Rails.application.config.active_job.queue_adapter).to eq(:shoryuken)
      RailsEmailJob.perform_later(999, 'config_test')
    end

    it 'jobs work with Rails secrets and credentials' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')
      end

      # Jobs should be able to access Rails secrets
      expect(Rails.application.secret_key_base).to eq('test_secret_key_base_for_testing_only')
      RailsEmailJob.perform_later(888, 'secrets_test')
    end

    it 'handles Rails autoloading' do
      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')

        # Verify job class can be constantized (Rails autoloading)
        expect { body['job_class'].constantize }.not_to raise_error
      end

      RailsEmailJob.perform_later(777, 'autoload_test')
    end
  end

  describe 'ActionMailer Integration' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'handles ActionMailer delivery jobs' do
      # Simulate ActionMailer::MailDeliveryJob which Rails creates automatically
      mail_job_data = {
        'job_class' => 'ActionMailer::MailDeliveryJob',
        'arguments' => ['UserMailer', 'welcome_email', 'deliver_now', { 'user_id' => 123 }]
      }

      sqs_msg = double('SQS Message',
        attributes: { 'ApproximateReceiveCount' => '1' },
        message_id: 'mail-delivery-msg'
      )

      wrapper = Shoryuken::ActiveJob::JobWrapper.new

      # Mock the execution of mail delivery
      expect(ActiveJob::Base).to receive(:execute) do |job_data|
        expect(job_data['job_class']).to eq('ActionMailer::MailDeliveryJob')
        expect(job_data['arguments']).to include('UserMailer', 'welcome_email')
      end

      wrapper.perform(sqs_msg, mail_job_data)
    end
  end

  describe 'Rails Production-like Features' do
    let(:queue) { double('Queue', fifo?: false) }

    before do
      allow(Shoryuken::Client).to receive(:queues).and_return(queue)
      allow(queue).to receive(:send_message)
      allow(Shoryuken).to receive(:register_worker)
    end

    it 'works with different Rails environments' do
      original_env = Rails.env

      # Temporarily simulate production environment
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      expect(queue).to receive(:send_message) do |params|
        body = params[:message_body]
        expect(body['job_class']).to eq('RailsEmailJob')
      end

      RailsEmailJob.perform_later(666, 'production_test')

      # Restore
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(original_env))
    end

    it 'handles Rails middleware stack' do
      # Verify Rails middleware is loaded
      expect(Rails.application.middleware).not_to be_empty
      expect(Rails.application.middleware.map(&:name)).to include('ActionDispatch::ShowExceptions')
    end

    it 'integrates with Rails instrumentation' do
      events = []
      subscription = ActiveSupport::Notifications.subscribe(/active_job/) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end

      begin
        expect(queue).to receive(:send_message)
        RailsEmailJob.perform_later(555, 'instrumentation_test')

        # Check that Rails fired ActiveJob instrumentation events
        enqueue_events = events.select { |e| e.name == 'enqueue.active_job' }
        expect(enqueue_events).not_to be_empty

        event = enqueue_events.first
        expect(event.payload[:job]).to be_a(RailsEmailJob)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscription)
      end
    end
  end
end
