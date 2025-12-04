#!/usr/bin/env ruby
# frozen_string_literal: true

# Middleware chain integration tests
# Tests middleware execution order, exception handling, and customization

begin
  require 'shoryuken'
rescue LoadError => e
  puts "Failed to load dependencies: #{e.message}"
  exit 1
end

# Track middleware execution order
$middleware_execution_order = []

# Custom middleware for testing execution order
class FirstMiddleware
  def call(worker, queue, sqs_msg, body)
    $middleware_execution_order << :first_before
    yield
    $middleware_execution_order << :first_after
  end
end

class SecondMiddleware
  def call(worker, queue, sqs_msg, body)
    $middleware_execution_order << :second_before
    yield
    $middleware_execution_order << :second_after
  end
end

class ThirdMiddleware
  def call(worker, queue, sqs_msg, body)
    $middleware_execution_order << :third_before
    yield
    $middleware_execution_order << :third_after
  end
end

# Middleware that doesn't yield (short-circuits)
class ShortCircuitMiddleware
  def call(worker, queue, sqs_msg, body)
    $middleware_execution_order << :short_circuit
    # Does not yield - stops chain execution
  end
end

# Middleware that raises an exception
class ExceptionMiddleware
  def call(worker, queue, sqs_msg, body)
    $middleware_execution_order << :exception_before
    raise StandardError, "Middleware exception"
  end
end

# Middleware with constructor arguments
class ConfigurableMiddleware
  def initialize(config_value)
    @config_value = config_value
  end

  def call(worker, queue, sqs_msg, body)
    $middleware_execution_order << "configurable_#{@config_value}".to_sym
    yield
  end
end

# Another configurable middleware for testing multiple instances
class AnotherConfigurableMiddleware
  def initialize(config_value)
    @config_value = config_value
  end

  def call(worker, queue, sqs_msg, body)
    $middleware_execution_order << "another_configurable_#{@config_value}".to_sym
    yield
  end
end

# Test worker
class MiddlewareTestWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'middleware-test', auto_delete: true

  def perform(sqs_msg, body)
    $middleware_execution_order << :worker_perform
  end
end

run_test_suite "Middleware Execution Order" do
  run_test "executes middleware in correct order (onion model)" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add FirstMiddleware
    chain.add SecondMiddleware
    chain.add ThirdMiddleware

    worker = MiddlewareTestWorker.new
    sqs_msg = double(:sqs_msg)
    body = "test body"

    chain.invoke(worker, 'test-queue', sqs_msg, body) do
      $middleware_execution_order << :worker_perform
    end

    expected_order = [
      :first_before, :second_before, :third_before,
      :worker_perform,
      :third_after, :second_after, :first_after
    ]
    assert_equal(expected_order, $middleware_execution_order)
  end

  run_test "prepend adds middleware at the beginning" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add SecondMiddleware
    chain.prepend FirstMiddleware

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    assert_equal(:first_before, $middleware_execution_order.first)
  end

  run_test "insert_before places middleware correctly" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add FirstMiddleware
    chain.add ThirdMiddleware
    chain.insert_before ThirdMiddleware, SecondMiddleware

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    first_idx = $middleware_execution_order.index(:first_before)
    second_idx = $middleware_execution_order.index(:second_before)
    third_idx = $middleware_execution_order.index(:third_before)

    assert(first_idx < second_idx, "First should be before Second")
    assert(second_idx < third_idx, "Second should be before Third")
  end

  run_test "insert_after places middleware correctly" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add FirstMiddleware
    chain.add ThirdMiddleware
    chain.insert_after FirstMiddleware, SecondMiddleware

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    first_idx = $middleware_execution_order.index(:first_before)
    second_idx = $middleware_execution_order.index(:second_before)
    third_idx = $middleware_execution_order.index(:third_before)

    assert(first_idx < second_idx, "First should be before Second")
    assert(second_idx < third_idx, "Second should be before Third")
  end
end

run_test_suite "Middleware Short-Circuit" do
  run_test "stops chain when middleware doesn't yield" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add FirstMiddleware
    chain.add ShortCircuitMiddleware
    chain.add ThirdMiddleware

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    assert_includes($middleware_execution_order, :first_before)
    assert_includes($middleware_execution_order, :short_circuit)
    refute($middleware_execution_order.include?(:third_before), "Third should not execute")
    refute($middleware_execution_order.include?(:worker), "Worker should not execute")
    assert_includes($middleware_execution_order, :first_after)
  end
end

run_test_suite "Middleware Exception Handling" do
  run_test "propagates exceptions through middleware chain" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add FirstMiddleware
    chain.add ExceptionMiddleware
    chain.add ThirdMiddleware

    exception_raised = false
    begin
      chain.invoke(nil, 'test', nil, nil) do
        $middleware_execution_order << :worker
      end
    rescue StandardError => e
      exception_raised = true
      assert_equal("Middleware exception", e.message)
    end

    assert(exception_raised, "Exception should have been raised")
    assert_includes($middleware_execution_order, :first_before)
    assert_includes($middleware_execution_order, :exception_before)
    refute($middleware_execution_order.include?(:third_before), "Third should not execute")
    refute($middleware_execution_order.include?(:worker), "Worker should not execute")
  end
end

run_test_suite "Middleware with Arguments" do
  run_test "supports middleware with constructor arguments" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add ConfigurableMiddleware, 'option_a'

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    assert_includes($middleware_execution_order, :configurable_option_a)
  end

  run_test "supports multiple configured middleware instances" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add ConfigurableMiddleware, 'first'
    chain.add AnotherConfigurableMiddleware, 'second'

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    assert_includes($middleware_execution_order, :configurable_first)
    assert_includes($middleware_execution_order, :another_configurable_second)
  end

  run_test "ignores duplicate middleware class (same class added twice)" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add ConfigurableMiddleware, 'first'
    chain.add ConfigurableMiddleware, 'second' # This is ignored

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    # Only the first instance should be added
    assert_includes($middleware_execution_order, :configurable_first)
    refute($middleware_execution_order.include?(:configurable_second), "Duplicate middleware should be ignored")
  end
end

run_test_suite "Middleware Chain Management" do
  run_test "removes middleware by class" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add FirstMiddleware
    chain.add SecondMiddleware
    chain.add ThirdMiddleware
    chain.remove SecondMiddleware

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    assert_includes($middleware_execution_order, :first_before)
    refute($middleware_execution_order.include?(:second_before), "Second should be removed")
    assert_includes($middleware_execution_order, :third_before)
  end

  run_test "clears all middleware" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new
    chain.add FirstMiddleware
    chain.add SecondMiddleware
    chain.clear

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    assert_equal([:worker], $middleware_execution_order)
  end

  run_test "checks if middleware exists" do
    chain = Shoryuken::Middleware::Chain.new
    chain.add FirstMiddleware

    assert(chain.exists?(FirstMiddleware))
    refute(chain.exists?(SecondMiddleware))
  end
end

run_test_suite "Empty Middleware Chain" do
  run_test "executes worker directly with empty chain" do
    $middleware_execution_order = []

    chain = Shoryuken::Middleware::Chain.new

    chain.invoke(nil, 'test', nil, nil) do
      $middleware_execution_order << :worker
    end

    assert_equal([:worker], $middleware_execution_order)
  end
end
