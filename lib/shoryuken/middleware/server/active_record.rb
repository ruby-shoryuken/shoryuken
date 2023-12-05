module Shoryuken
  module Middleware
    module Server
      class ActiveRecord
        def call(*_args)
          yield
        ensure
          ::ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
        end
      end
    end
  end
end
