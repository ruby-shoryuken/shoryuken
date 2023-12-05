module Shoryuken
  module Middleware
    module Server
      class ActiveRecord
        def call(*_args)
          yield
        ensure
          if ::ActiveRecord.version >= Gem::Version.new('7.1')
            ::ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
          else
            ::ActiveRecord::Base.clear_active_connections!
          end
        end
      end
    end
  end
end
