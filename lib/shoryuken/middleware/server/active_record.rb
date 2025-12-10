# frozen_string_literal: true

module Shoryuken
  module Middleware
    # Server-side middleware that runs around message processing
    module Server
      # Middleware that clears ActiveRecord connections after message processing.
      # Ensures database connections are returned to the pool after each job.
      class ActiveRecord
        # Processes a message and clears database connections afterwards
        #
        # @param _args [Array] middleware call arguments (unused)
        # @yield continues to the next middleware in the chain
        # @return [void]
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
