# frozen_string_literal: true

# Empty middleware chain executes worker block directly

chain = Shoryuken::Middleware::Chain.new

chain.invoke(nil, 'test', nil, nil) do
  DT[:calls] << :worker
end

assert_equal([:worker], DT[:calls])
