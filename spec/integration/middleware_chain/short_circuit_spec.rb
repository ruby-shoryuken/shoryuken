# frozen_string_literal: true

# Middleware can short-circuit the chain by not calling the block

def create_middleware(name)
  Class.new do
    define_method(:call) do |worker, queue, sqs_msg, body, &block|
      DT[:calls] << :"#{name}_before"
      block.call
      DT[:calls] << :"#{name}_after"
    end
  end
end

def create_short_circuit_middleware
  Class.new do
    define_method(:call) do |worker, queue, sqs_msg, body, &block|
      DT[:calls] << :short_circuit
    end
  end
end

first = create_middleware(:first)
short_circuit = create_short_circuit_middleware
third = create_middleware(:third)

chain = Shoryuken::Middleware::Chain.new
chain.add first
chain.add short_circuit
chain.add third

chain.invoke(nil, 'test', nil, nil) do
  DT[:calls] << :worker
end

assert_includes(DT[:calls], :first_before)
assert_includes(DT[:calls], :short_circuit)
refute(DT[:calls].include?(:third_before), "Third should not execute")
refute(DT[:calls].include?(:worker), "Worker should not execute")
assert_includes(DT[:calls], :first_after)
