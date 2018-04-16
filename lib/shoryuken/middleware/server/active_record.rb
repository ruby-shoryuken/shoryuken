module Shoryuken
  module Middleware
    module Server
      class ActiveRecord
        def call(*_args)
          yield
        ensure
          ::ActiveRecord::Base.clear_active_connections!
        end
      end
    end
  end
end
