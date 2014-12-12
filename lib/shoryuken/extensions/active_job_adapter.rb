# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters
# Ref: https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/extensions/active_record.rb
# Multiple queues ref: https://github.com/rails/rails/blob/master/activejob/lib/active_job/queue_adapters/sneakers_adapter.rb

require 'shoryuken'

module ActiveJob
  module QueueAdapters
    # == Shoryuken adapter for Active Job
    #
    # Shoryuken ("sho-ryu-ken") is a super-efficient AWS SQS thread based message processor.
    #
    # Read more about Shoryuken {here}[https://github.com/phstc/shoryuken].
    #
    # To use Shoryuken set the queue_adapter config to +:shoryuken+.
    #
    #   Rails.application.config.active_job.queue_adapter = :shoryuken
    class ShoryukenAdapter
      class << self
        def enqueue(job) #:nodoc:
          # TODO use job.queue_name
          JobWrapper.perform_async(job.serialize)
        end

        def enqueue_at(job, timestamp) #:nodoc:
          # TODO use job.queue_name
          JobWrapper.perform_at(timestamp, job.serialize)
        end
      end

      class JobWrapper #:nodoc:
        include Shoryuken::Worker

        shoryuken_options queue: 'default', body_parser: :json

        def perform(sqs_msg, hash)
          Base.execute hash
        end
      end
    end
  end
end
