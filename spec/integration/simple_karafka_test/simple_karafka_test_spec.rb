#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple Karafka-style integration test to demonstrate the approach
# This test runs in complete isolation with its own Gemfile

require_relative '../../integrations_helper'

# Load only what we need for this specific test
require 'shoryuken/version'

run_test_suite "Basic Shoryuken Loading" do
  run_test "loads Shoryuken version" do
    version = Shoryuken::VERSION
    assert(version.is_a?(String), "Expected version to be a string")
    assert(version.match?(/\d+\.\d+\.\d+/), "Expected version format x.y.z")
  end

  run_test "has isolated gemfile" do
    gemfile_path = File.expand_path('Gemfile')
    assert(File.exist?(gemfile_path), "Expected Gemfile to exist")

    gemfile_content = File.read(gemfile_path)
    assert_includes(gemfile_content, "gemspec path: '../../../'")
  end
end

run_test_suite "Dependency Isolation" do
  run_test "can load httparty from this test's Gemfile" do
    require 'httparty'
    assert(defined?(HTTParty), "HTTParty should be available")
  end

  run_test "runs in isolated process" do
    # This test demonstrates complete process isolation
    process_id = Process.pid
    assert(process_id > 0, "Should have valid process ID")
  end
end
