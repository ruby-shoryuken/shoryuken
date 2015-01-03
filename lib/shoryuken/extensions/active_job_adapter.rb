# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters

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
          register_worker!(job)

          Shoryuken::Client.send_message(job.queue_name, job.serialize, message_attributes: message_attributes)
        end

        def enqueue_at(job, timestamp) #:nodoc:
          register_worker!(job)

          delay = timestamp - Time.current.to_f
          raise 'The maximum allowed delay is 15 minutes' if delay > 15.minutes

          Shoryuken::Client.send_message(job.queue_name, job.serialize, delay_seconds: delay,
                                                                        message_attributes: message_attributes)
        end


        private

        def register_worker!(job)
          Shoryuken.register_worker(job.queue_name, JobWrapper)
        end

        def message_attributes
          @message_attributes ||= {
            'shoryuken_class' => {
              string_value: JobWrapper.to_s,
              data_type: 'String'
            }
          }
        end
      end

      class JobWrapper #:nodoc:
        include Shoryuken::Worker

        shoryuken_options body_parser: :json, auto_delete: true

        def perform(sqs_msg, hash)
          Base.execute hash
        end
      end
    end
  end
end
