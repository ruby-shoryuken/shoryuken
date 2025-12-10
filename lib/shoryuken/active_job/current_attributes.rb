# frozen_string_literal: true

require 'active_support/current_attributes'
require 'active_job'

module Shoryuken
  module ActiveJob
    # Middleware to persist Rails CurrentAttributes across job execution.
    #
    # This ensures that request-scoped context (like current user, tenant, locale)
    # automatically flows from the code that enqueues a job to the job's execution.
    #
    # Based on Sidekiq's approach to persisting current attributes.
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

        def serialize(attrs)
          ::ActiveJob::Arguments.serialize([attrs]).first
        end

        def deserialize(attrs)
          ::ActiveJob::Arguments.deserialize([attrs]).first
        end
      end

      class << self
        # @return [Hash<String, String>] registered CurrentAttributes classes mapped to keys
        attr_reader :cattrs

        # Register CurrentAttributes classes to persist across job execution.
        #
        # @param klasses [Array<String, Class>] CurrentAttributes class names or classes
        # @example
        #   Shoryuken::ActiveJob::CurrentAttributes.persist('Current')
        #   Shoryuken::ActiveJob::CurrentAttributes.persist(Current, RequestContext)
        def persist(*klasses)
          @cattrs ||= {}

          klasses.flatten.each_with_index do |klass, idx|
            key = @cattrs.empty? ? 'cattr' : "cattr_#{idx}"
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
        def perform(sqs_msg, hash)
          klasses_to_reset = []

          CurrentAttributes.cattrs&.each do |key, klass_name|
            next unless hash.key?(key)

            klass = klass_name.constantize
            klasses_to_reset << klass

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
          klasses_to_reset.each(&:reset)
        end
      end
    end
  end
end
