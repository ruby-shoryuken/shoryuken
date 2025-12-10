# frozen_string_literal: true

# Middleware executes in onion model order (first-in wraps outermost)

def create_middleware(name)
  Class.new do
    define_method(:call) do |worker, queue, sqs_msg, body, &block|
      DT[:order] << :"#{name}_before"
      block.call
      DT[:order] << :"#{name}_after"
    end
  end
end

first = create_middleware(:first)
second = create_middleware(:second)
third = create_middleware(:third)

chain = Shoryuken::Middleware::Chain.new
chain.add first
chain.add second
chain.add third

chain.invoke(nil, 'test-queue', nil, nil) do
  DT[:order] << :worker_perform
end

expected_order = [
  :first_before, :second_before, :third_before,
  :worker_perform,
  :third_after, :second_after, :first_after
]
assert_equal(expected_order, DT[:order])
