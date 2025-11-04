#!/usr/bin/env ruby
# frozen_string_literal: true

# Rails framework edge cases integration test for Rails 7.0
# Tests specific Rails 7.0 + concurrent-ruby + zeitwerk combinations
# This test runs in complete isolation with its own specific Gemfile

require_relative '../../integrations_helper'

# Only run if Rails is available
begin
  # Rails 7.0 + Ruby 3.4 compatibility
  require 'logger'
  require 'rails/all'
  require 'rack/test'

  # Load Shoryuken before Rails to ensure adapter is available
  require 'shoryuken'

  RAILS_AVAILABLE = true
rescue LoadError
  RAILS_AVAILABLE = false
end

unless RAILS_AVAILABLE
  puts "[SKIP] Rails not available for framework edge case tests"
  exit 0
end

# Test Rails application for edge cases
class EdgeCaseRailsApp < Rails::Application
  config.load_defaults '7.0'
  config.active_job.queue_adapter = :shoryuken
  config.eager_load = false
  config.cache_store = :memory_store
  config.logger = Logger.new('/dev/null')
  config.log_level = :fatal
  config.secret_key_base = 'edge_case_test_secret'

  # Edge case: Specific Zeitwerk configuration
  config.autoloader = :zeitwerk
end

# Initialize Rails
app = EdgeCaseRailsApp.new
app.initialize!
Rails.application = app

# Edge case job for testing specific Rails 7.0 + concurrent-ruby interaction
class EdgeCaseJob < ActiveJob::Base
  queue_as :edge_cases

  def perform(scenario)
    case scenario
    when 'concurrent_ruby_interaction'
      # Test concurrent-ruby specific version interaction
      require 'concurrent'
      future = Concurrent::Future.execute { "concurrent task" }
      future.value
    when 'zeitwerk_autoload_test'
      # Test zeitwerk autoloading edge case
      "Zeitwerk version: #{Zeitwerk::VERSION}"
    when 'rails_cache_edge_case'
      # Edge case with Rails cache in specific Rails 7.0 version
      Rails.cache.write('edge_test', 'value')
      Rails.cache.read('edge_test')
    else
      "Unknown edge case: #{scenario}"
    end
  end
end


run_test_suite "Rails 7.0 Framework Edge Cases" do
  run_test "handles concurrent-ruby gem version interaction" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    EdgeCaseJob.perform_later('concurrent_ruby_interaction')

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal("EdgeCaseJob", message_body["job_class"])
    assert_equal(['concurrent_ruby_interaction'], message_body["arguments"])
  end

  run_test "works with zeitwerk specific version" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    EdgeCaseJob.perform_later('zeitwerk_autoload_test')

    job = job_capture.last_job
    message_body = job[:message_body]
    assert_equal("EdgeCaseJob", message_body["job_class"])
    assert_includes(message_body["arguments"], 'zeitwerk_autoload_test')
  end

  run_test "Rails cache interaction edge case" do
    job_capture = JobCapture.new
    job_capture.start_capturing

    EdgeCaseJob.perform_later('rails_cache_edge_case')

    # Should enqueue without errors
    assert_equal(1, job_capture.job_count)
  end
end

run_test_suite "Dependency Version Verification" do
  run_test "uses correct Rails 7.0 version" do
    require 'rails/version'
    version = Rails::VERSION::STRING
    assert(version.start_with?('7.0'), "Expected Rails 7.0, got #{version}")
  end

  run_test "uses specific concurrent-ruby version" do
    require 'concurrent/version'
    version = Concurrent::VERSION
    assert(version.start_with?('1.2'), "Expected concurrent-ruby 1.2.x, got #{version}")
  end

  run_test "uses specific zeitwerk version" do
    require 'zeitwerk'
    version = Zeitwerk::VERSION
    assert(version.start_with?('2.6'), "Expected zeitwerk 2.6.x, got #{version}")
  end
end

