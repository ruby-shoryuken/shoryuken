# frozen_string_literal: true

# Integration test helper for process-isolated testing

require 'timeout'
require 'json'
require 'securerandom'
require 'aws-sdk-sqs'
require 'shoryuken'
require 'singleton'

# Thread-safe data collector for integration tests
# Inspired by Karafka's DataCollector pattern
# Usage: DT[:key] << value, DT[:key].size, DT.clear
class DataCollector
  include Singleton

  MUTEX = Mutex.new
  private_constant :MUTEX

  attr_reader :queues, :data

  class << self
    def queue
      instance.queue
    end

    def queues
      instance.queues
    end

    def data
      instance.data
    end

    def [](key)
      MUTEX.synchronize { data[key] }
    end

    def []=(key, value)
      MUTEX.synchronize { data[key] = value }
    end

    def uuids(amount)
      Array.new(amount) { uuid }
    end

    def uuid
      "it-#{SecureRandom.uuid[0, 8]}"
    end

    def clear
      MUTEX.synchronize { instance.clear }
    end

    def key?(key)
      instance.data.key?(key)
    end
  end

  def initialize
    @mutex = Mutex.new
    @queues = Array.new(100) { "it-#{SecureRandom.hex(6)}" }
    @data = Hash.new do |hash, key|
      @mutex.synchronize do
        break hash[key] if hash.key?(key)

        hash[key] = []
      end
    end
  end

  def queue
    queues.first
  end

  def clear
    @mutex.synchronize do
      @queues.clear
      @queues.concat(Array.new(100) { "it-#{SecureRandom.hex(6)}" })
      @data.clear
    end
  end
end

# Short alias for DataCollector
DT = DataCollector

module IntegrationsHelper
  class TestFailure < StandardError; end

  # Assertions
  def assert(condition, message = "Assertion failed")
    raise TestFailure, message unless condition
  end

  def assert_equal(expected, actual, message = nil)
    message ||= "Expected #{expected.inspect}, got #{actual.inspect}"
    assert(expected == actual, message)
  end

  def assert_includes(collection, item, message = nil)
    message ||= "Expected #{collection.inspect} to include #{item.inspect}"
    assert(collection.include?(item), message)
  end

  def refute(condition, message = "Refutation failed")
    assert(!condition, message)
  end

  # Configure Shoryuken to use LocalStack for real SQS integration tests
  def setup_localstack
    Aws.config[:stub_responses] = false

    sqs_client = Aws::SQS::Client.new(
      region: 'us-east-1',
      endpoint: 'http://localhost:4566',
      access_key_id: 'fake',
      secret_access_key: 'fake'
    )

    Shoryuken.options[:concurrency] = 25
    Shoryuken.options[:delay] = 0
    Shoryuken.options[:timeout] = 8

    executor = Concurrent::CachedThreadPool.new(auto_terminate: true)
    Shoryuken.define_singleton_method(:launcher_executor) { executor }

    Shoryuken.configure_client { |config| config.sqs_client = sqs_client }
    Shoryuken.configure_server { |config| config.sqs_client = sqs_client }
  end

  # Queue helpers
  def create_test_queue(queue_name, attributes: {})
    Shoryuken::Client.sqs.create_queue(queue_name: queue_name, attributes: attributes)
  end

  def delete_test_queue(queue_name)
    queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
    Shoryuken::Client.sqs.delete_queue(queue_url: queue_url)
  rescue Aws::SQS::Errors::NonExistentQueue
  end

  def create_fifo_queue(queue_name)
    create_test_queue(queue_name, attributes: {
      'FifoQueue' => 'true',
      'ContentBasedDeduplication' => 'true'
    })
  end

  # Poll until condition met
  def poll_queues_until(timeout: 15)
    launcher = Shoryuken::Launcher.new
    launcher.start
    Timeout.timeout(timeout) { sleep 0.5 until yield }
  ensure
    launcher.stop
  end

  # Simple mock object
  def double(_name = nil)
    Object.new
  end

  # Job capture for ActiveJob tests
  class JobCapture
    attr_reader :jobs

    def initialize
      @jobs = []
    end

    def start_capturing
      @jobs.clear
      capture = self

      queue_mock = Object.new
      queue_mock.define_singleton_method(:fifo?) { false }
      queue_mock.define_singleton_method(:send_message) do |params|
        capture.jobs << {
          queue: params[:queue_name] || :default,
          message_body: params[:message_body],
          delay_seconds: params[:delay_seconds],
          message_attributes: params[:message_attributes]
        }
      end

      Shoryuken::Client.define_singleton_method(:queues) do |queue_name = nil|
        queue_mock.define_singleton_method(:name) { queue_name } if queue_name
        queue_name ? queue_mock : { default: queue_mock }
      end

      Shoryuken.define_singleton_method(:register_worker) { |*| nil }
    end

    def last_job
      @jobs.last
    end

    def job_count
      @jobs.size
    end
  end
end

include IntegrationsHelper
