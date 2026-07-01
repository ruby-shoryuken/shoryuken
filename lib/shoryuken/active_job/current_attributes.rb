# frozen_string_literal: true

require 'active_support/current_attributes'
require 'active_job'

module Shoryuken
  # ActiveJob integration module for Shoryuken
  module ActiveJob
    # Middleware to persist Rails CurrentAttributes across job execution.
    #
    # This ensures that request-scoped context (like current user, tenant, locale)
    # automatically flows from the code that enqueues a job to the job's execution.
    #
    # Based on Sidekiq's approach to persisting current attributes, with one
    # deliberate difference in cleanup: Sidekiq only touches the classes carried
    # by a job and leaves the general reset to the Rails executor it runs jobs
    # inside. Shoryuken does not run jobs inside that executor by default, so the
    # loader resets every registered class after each job itself - see the note
    # on {Loading#perform}.
    #
    # @example Setup in initializer
    #   require 'shoryuken/active_job/current_attributes'
    #   Shoryuken::ActiveJob::CurrentAttributes.persist('MyApp::Current')
    #
    # @example Multiple CurrentAttributes classes
    #   Shoryuken::ActiveJob::CurrentAttributes.persist('MyApp::Current', 'MyApp::RequestContext')
    #
    # @see https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html
    # @see https://github.com/sidekiq/sidekiq/blob/main/lib/sidekiq/middleware/current_attributes.rb
    module CurrentAttributes
      # Serializer for current attributes using ActiveJob::Arguments.
      # Supports Symbols and GlobalID objects.
      module Serializer
        module_function

        # Serializes attributes hash for SQS message storage
        #
        # @param attrs [Hash] the attributes to serialize
        # @return [Object] the serialized attributes
        def serialize(attrs)
          ::ActiveJob::Arguments.serialize([attrs]).first
        end

        # Deserializes attributes hash from SQS message
        #
        # @param attrs [Object] the serialized attributes
        # @return [Hash] the deserialized attributes
        def deserialize(attrs)
          ::ActiveJob::Arguments.deserialize([attrs]).first
        end
      end

      class << self
        # @return [Hash{String => String}] serialization keys mapped to CurrentAttributes class names
        attr_reader :cattrs

        # Register CurrentAttributes classes to persist across job execution.
        #
        # @param klasses [Array<String, Class>] CurrentAttributes class names or classes
        # @example
        #   Shoryuken::ActiveJob::CurrentAttributes.persist('Current')
        #   Shoryuken::ActiveJob::CurrentAttributes.persist(Current, RequestContext)
        def persist(*klasses)
          @cattrs ||= {}

          klasses.flatten.each do |klass|
            # Key off the running registry size, not the per-call index, so that
            # registering classes across separate persist calls still produces
            # distinct keys (a per-call index restarts at 0 each call and would
            # overwrite earlier registrations).
            key = @cattrs.empty? ? 'cattr' : "cattr_#{@cattrs.size}"
            @cattrs[key] = klass.to_s
          end

          # Prepend the persistence module to the adapter for serialization
          unless ::ActiveJob::QueueAdapters::ShoryukenAdapter.ancestors.include?(Persistence)
            ::ActiveJob::QueueAdapters::ShoryukenAdapter.prepend(Persistence)
          end

          # Prepend the loading module to JobWrapper for deserialization
          unless Shoryuken::ActiveJob::JobWrapper.ancestors.include?(Loading)
            Shoryuken::ActiveJob::JobWrapper.prepend(Loading)
          end
        end
      end

      # Module prepended to ShoryukenAdapter to serialize CurrentAttributes on enqueue.
      module Persistence
        private

        # Builds the SQS message with CurrentAttributes data
        #
        # @param queue [Shoryuken::Queue] the target queue
        # @param job [ActiveJob::Base] the job being enqueued
        # @return [Hash] the message parameters
        def message(queue, job)
          hash = super

          CurrentAttributes.cattrs&.each do |key, klass_name|
            next if hash[:message_body].key?(key)

            klass = klass_name.constantize
            attrs = klass.attributes
            next if attrs.empty?

            hash[:message_body][key] = Serializer.serialize(attrs)
          end

          hash
        end
      end

      # Module prepended to JobWrapper to restore CurrentAttributes on execute.
      module Loading
        # Performs the job after restoring CurrentAttributes
        #
        # @param sqs_msg [Shoryuken::Message] the SQS message
        # @param hash [Hash] the deserialized job data
        # @return [void]
        def perform(sqs_msg, hash)
          CurrentAttributes.cattrs&.each do |key, klass_name|
            next unless hash.key?(key)

            klass = klass_name.constantize

            begin
              attrs = Serializer.deserialize(hash[key])
              attrs.each do |attr_name, value|
                klass.public_send(:"#{attr_name}=", value) if klass.respond_to?(:"#{attr_name}=")
              end
            rescue => e
              # Log but don't fail if attributes can't be restored
              # (e.g., attribute removed between enqueue and execute)
              Shoryuken.logger.warn("Failed to restore CurrentAttributes #{klass_name}: #{e.message}")
            end
          end

          super
        ensure
          # Reset every registered CurrentAttributes class after the job - not
          # only the ones whose key was in this message.
          #
          # Why unconditional (and why this differs from Sidekiq): Sidekiq's
          # loader only touches classes present in the job and relies on the
          # Rails executor - which it runs every job inside - to reset all
          # CurrentAttributes between units of work. Shoryuken has no such safety
          # net: it wraps a job in the reloader/executor only when
          # `enable_reloading` is set, which is off by default, so nothing else
          # clears CurrentAttributes between jobs.
          #
          # A blanket reset here is therefore the only thing guaranteeing a clean
          # thread. Resetting only the present keys leaks whenever a value ends up
          # set during a job whose message carried no cattr key - e.g. the worker
          # (or code it calls) writes to Current, on a keyless message (empty
          # context at enqueue, a different producer, or persist configured after
          # the message was queued). CurrentAttributes are thread-local and the
          # pool reuses threads, so that value would surface in the next job.
          CurrentAttributes.cattrs&.each_value do |klass_name|
            klass_name.constantize.reset
          rescue => e
            Shoryuken.logger.warn("Failed to reset CurrentAttributes #{klass_name}: #{e.message}")
          end
        end
      end
    end
  end
end
