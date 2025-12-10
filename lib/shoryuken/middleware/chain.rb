# frozen_string_literal: true

module Shoryuken
  # Middleware provides a way to wrap message processing with custom logic,
  # similar to Rack middleware in web applications. Middleware runs on the server
  # side and can perform setup, teardown, error handling, and monitoring around
  # job execution.
  #
  # Middleware classes must implement a `call` method that accepts the worker instance,
  # queue name, and SQS message, and must yield to continue the middleware chain.
  #
  # ## Global Middleware Configuration
  #
  # Configure middleware globally for all workers:
  #
  #   Shoryuken.configure_server do |config|
  #     config.server_middleware do |chain|
  #       chain.add MyServerHook
  #       chain.remove Shoryuken::Middleware::Server::ActiveRecord
  #     end
  #   end
  #
  # ## Per-Worker Middleware Configuration
  #
  # Configure middleware for specific workers:
  #
  #   class MyWorker
  #     include Shoryuken::Worker
  #
  #     server_middleware do |chain|
  #       chain.add MyWorkerSpecificMiddleware
  #     end
  #   end
  #
  # ## Middleware Ordering
  #
  # Insert middleware at specific positions in the chain:
  #
  #   # Insert before existing middleware
  #   chain.insert_before Shoryuken::Middleware::Server::ActiveRecord, MyDatabaseSetup
  #
  #   # Insert after existing middleware
  #   chain.insert_after Shoryuken::Middleware::Server::Timing, MyMetricsCollector
  #
  #   # Add to beginning of chain
  #   chain.prepend MyFirstMiddleware
  #
  # ## Example Middleware Implementations
  #
  #   # Basic logging middleware
  #   class LoggingMiddleware
  #     def call(worker_instance, queue, sqs_msg, body)
  #       puts "Processing #{sqs_msg.message_id} on #{queue}"
  #       start_time = Time.now
  #       yield
  #       puts "Completed in #{Time.now - start_time}s"
  #     end
  #   end
  #
  #   # Error reporting middleware
  #   class ErrorReportingMiddleware
  #     def call(worker_instance, queue, sqs_msg, body)
  #       yield
  #     rescue => error
  #       ErrorReporter.notify(error, {
  #         worker: worker_instance.class.name,
  #         queue: queue,
  #         message_id: sqs_msg.message_id
  #       })
  #       raise
  #     end
  #   end
  #
  #   # Performance monitoring middleware
  #   class MetricsMiddleware
  #     def call(worker_instance, queue, sqs_msg, body)
  #       start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  #       yield
  #       duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
  #       StatsD.timing("shoryuken.#{worker_instance.class.name.underscore}.duration", duration)
  #     end
  #   end
  #
  # @see Shoryuken::Middleware::Chain Middleware chain management
  # @see https://github.com/ruby-shoryuken/shoryuken/wiki/Middleware Comprehensive middleware guide
  module Middleware
    # Manages a chain of middleware classes that will be instantiated and invoked
    # in sequence around message processing. Provides methods for adding, removing,
    # and reordering middleware.
    class Chain
      # @return [Array<Entry>] The ordered list of middleware entries
      attr_reader :entries

      # Creates a new middleware chain.
      #
      # @yield [Chain] The chain instance for configuration
      # @example Creating and configuring a chain
      #   chain = Shoryuken::Middleware::Chain.new do |c|
      #     c.add MyMiddleware
      #     c.add AnotherMiddleware, option: 'value'
      #   end
      def initialize
        @entries = []
        yield self if block_given?
      end

      # Creates a copy of this middleware chain.
      #
      # @return [Chain] A new chain with the same middleware entries
      def dup
        self.class.new.tap { |new_chain| new_chain.entries.replace(entries) }
      end

      # Removes all instances of the specified middleware class from the chain.
      #
      # @param klass [Class] The middleware class to remove
      # @return [Array<Entry>] The removed entries
      # @example Removing ActiveRecord middleware
      #   chain.remove Shoryuken::Middleware::Server::ActiveRecord
      def remove(klass)
        entries.delete_if { |entry| entry.klass == klass }
      end

      # Adds middleware to the end of the chain. Does nothing if the middleware
      # class is already present in the chain.
      #
      # @param klass [Class] The middleware class to add
      # @param args [Array] Arguments to pass to the middleware constructor
      # @example Adding middleware with arguments
      #   chain.add MyMiddleware, timeout: 30, retries: 3
      def add(klass, *args)
        entries << Entry.new(klass, *args) unless exists?(klass)
      end

      # Adds middleware to the beginning of the chain. Does nothing if the middleware
      # class is already present in the chain.
      #
      # @param klass [Class] The middleware class to prepend
      # @param args [Array] Arguments to pass to the middleware constructor
      # @example Adding middleware to run first
      #   chain.prepend AuthenticationMiddleware
      def prepend(klass, *args)
        entries.insert(0, Entry.new(klass, *args)) unless exists?(klass)
      end

      # Inserts middleware immediately before another middleware class.
      # If the new middleware already exists, it's moved to the new position.
      #
      # @param oldklass [Class] The existing middleware to insert before
      # @param newklass [Class] The middleware class to insert
      # @param args [Array] Arguments to pass to the middleware constructor
      # @example Insert database setup before ActiveRecord middleware
      #   chain.insert_before Shoryuken::Middleware::Server::ActiveRecord, DatabaseSetup
      def insert_before(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
        i = entries.find_index { |entry| entry.klass == oldklass } || 0
        entries.insert(i, new_entry)
      end

      # Inserts middleware immediately after another middleware class.
      # If the new middleware already exists, it's moved to the new position.
      #
      # @param oldklass [Class] The existing middleware to insert after
      # @param newklass [Class] The middleware class to insert
      # @param args [Array] Arguments to pass to the middleware constructor
      # @example Insert metrics collection after timing middleware
      #   chain.insert_after Shoryuken::Middleware::Server::Timing, MetricsCollector
      def insert_after(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
        i = entries.find_index { |entry| entry.klass == oldklass } || entries.count - 1
        entries.insert(i + 1, new_entry)
      end

      # Checks if a middleware class is already in the chain.
      #
      # @param klass [Class] The middleware class to check for
      # @return [Boolean] True if the middleware is in the chain
      def exists?(klass)
        entries.any? { |entry| entry.klass == klass }
      end

      # Creates instances of all middleware classes in the chain.
      #
      # @return [Array] Array of middleware instances
      def retrieve
        entries.map(&:make_new)
      end

      # Removes all middleware from the chain.
      #
      # @return [Array] Empty array
      def clear
        entries.clear
      end

      # Invokes the middleware chain with the given arguments.
      # Each middleware's call method will be invoked in sequence,
      # with control passed through yielding.
      #
      # @param args [Array] arguments to pass to each middleware
      # @param final_action [Proc] the final action to perform after all middleware
      # @return [void]
      def invoke(*args, &final_action)
        chain = retrieve.dup
        traverse_chain = lambda do
          if chain.empty?
            final_action.call
          else
            chain.shift.call(*args, &traverse_chain)
          end
        end
        traverse_chain.call
      end
    end
  end
end
