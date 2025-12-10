# frozen_string_literal: true

# Middleware can be removed from the chain

def create_middleware(name)
  Class.new do
    define_method(:call) do |worker, queue, sqs_msg, body, &block|
      DT[:calls] << :"#{name}_before"
      block.call
      DT[:calls] << :"#{name}_after"
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
chain.remove second

chain.invoke(nil, 'test', nil, nil) do
  DT[:calls] << :worker
end

assert_includes(DT[:calls], :first_before)
refute(DT[:calls].include?(:second_before), "Second should be removed")
assert_includes(DT[:calls], :third_before)
