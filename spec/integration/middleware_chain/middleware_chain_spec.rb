# frozen_string_literal: true

# Middleware chain integration tests
# Tests middleware execution order and chain management

DT.clear

# Custom middleware for testing execution order
class FirstMiddleware
  def call(worker, queue, sqs_msg, body)
    DT[:order] << :first_before
    yield
    DT[:order] << :first_after
  end
end

class SecondMiddleware
  def call(worker, queue, sqs_msg, body)
    DT[:order] << :second_before
    yield
    DT[:order] << :second_after
  end
end

class ThirdMiddleware
  def call(worker, queue, sqs_msg, body)
    DT[:order] << :third_before
    yield
    DT[:order] << :third_after
  end
end

# Middleware that doesn't yield (short-circuits)
class ShortCircuitMiddleware
  def call(worker, queue, sqs_msg, body)
    DT[:order] << :short_circuit
    # Does not yield - stops chain execution
  end
end

# Test worker
class MiddlewareTestWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'middleware-test', auto_delete: true

  def perform(sqs_msg, body)
    DT[:order] << :worker_perform
  end
end

# Test middleware execution order (onion model)
chain = Shoryuken::Middleware::Chain.new
chain.add FirstMiddleware
chain.add SecondMiddleware
chain.add ThirdMiddleware

worker = MiddlewareTestWorker.new
sqs_msg = double(:sqs_msg)
body = "test body"

chain.invoke(worker, 'test-queue', sqs_msg, body) do
  DT[:order] << :worker_perform
end

expected_order = [
  :first_before, :second_before, :third_before,
  :worker_perform,
  :third_after, :second_after, :first_after
]
assert_equal(expected_order, DT[:order])

# Test short-circuit behavior
DT.clear

chain2 = Shoryuken::Middleware::Chain.new
chain2.add FirstMiddleware
chain2.add ShortCircuitMiddleware
chain2.add ThirdMiddleware

chain2.invoke(nil, 'test', nil, nil) do
  DT[:order] << :worker
end

assert_includes(DT[:order], :first_before)
assert_includes(DT[:order], :short_circuit)
refute(DT[:order].include?(:third_before), "Third should not execute")
refute(DT[:order].include?(:worker), "Worker should not execute")
assert_includes(DT[:order], :first_after)

# Test middleware removal
DT.clear

chain3 = Shoryuken::Middleware::Chain.new
chain3.add FirstMiddleware
chain3.add SecondMiddleware
chain3.add ThirdMiddleware
chain3.remove SecondMiddleware

chain3.invoke(nil, 'test', nil, nil) do
  DT[:order] << :worker
end

assert_includes(DT[:order], :first_before)
refute(DT[:order].include?(:second_before), "Second should be removed")
assert_includes(DT[:order], :third_before)

# Test empty chain
DT.clear

chain4 = Shoryuken::Middleware::Chain.new

chain4.invoke(nil, 'test', nil, nil) do
  DT[:order] << :worker
end

assert_equal([:worker], DT[:order])
