# frozen_string_literal: true

# Middleware chain integration tests
# Tests middleware execution order and chain management

# Helper to create middleware that tracks execution to a specific DT key
def create_middleware(name, key)
  Class.new do
    define_method(:call) do |worker, queue, sqs_msg, body, &block|
      DT[key] << :"#{name}_before"
      block.call
      DT[key] << :"#{name}_after"
    end
  end
end

# Middleware that doesn't yield (short-circuits)
def create_short_circuit_middleware(key)
  Class.new do
    define_method(:call) do |worker, queue, sqs_msg, body, &block|
      DT[key] << :short_circuit
      # Does not call block - stops chain execution
    end
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

# Test 1: middleware execution order (onion model)
first = create_middleware(:first, :order)
second = create_middleware(:second, :order)
third = create_middleware(:third, :order)

chain = Shoryuken::Middleware::Chain.new
chain.add first
chain.add second
chain.add third

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

# Test 2: short-circuit behavior
first_sc = create_middleware(:first, :short_circuit)
short_circuit = create_short_circuit_middleware(:short_circuit)
third_sc = create_middleware(:third, :short_circuit)

chain2 = Shoryuken::Middleware::Chain.new
chain2.add first_sc
chain2.add short_circuit
chain2.add third_sc

chain2.invoke(nil, 'test', nil, nil) do
  DT[:short_circuit] << :worker
end

assert_includes(DT[:short_circuit], :first_before)
assert_includes(DT[:short_circuit], :short_circuit)
refute(DT[:short_circuit].include?(:third_before), "Third should not execute")
refute(DT[:short_circuit].include?(:worker), "Worker should not execute")
assert_includes(DT[:short_circuit], :first_after)

# Test 3: middleware removal
first_rm = create_middleware(:first, :removal)
second_rm = create_middleware(:second, :removal)
third_rm = create_middleware(:third, :removal)

chain3 = Shoryuken::Middleware::Chain.new
chain3.add first_rm
chain3.add second_rm
chain3.add third_rm
chain3.remove second_rm

chain3.invoke(nil, 'test', nil, nil) do
  DT[:removal] << :worker
end

assert_includes(DT[:removal], :first_before)
refute(DT[:removal].include?(:second_before), "Second should be removed")
assert_includes(DT[:removal], :third_before)

# Test 4: empty chain
chain4 = Shoryuken::Middleware::Chain.new

chain4.invoke(nil, 'test', nil, nil) do
  DT[:empty_chain] << :worker
end

assert_equal([:worker], DT[:empty_chain])
