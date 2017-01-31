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
        def instance
          # https://github.com/phstc/shoryuken/pull/174#issuecomment-174555657
          @instance ||= new
        end

        def enqueue(job)
          instance.enqueue(job)
        end

        def enqueue_at(job, timestamp)
          instance.enqueue_at(job, timestamp)
        end
      end

      def enqueue(job) #:nodoc:
        register_worker!(job)

        queue = Shoryuken::Client.queues(job.queue_name)
        queue.send_message(message(job))
      end

      def enqueue_at(job, timestamp) #:nodoc:
        register_worker!(job)

        delay = (timestamp - Time.current.to_f).round
        raise 'The maximum allowed delay is 15 minutes' if delay > 15.minutes

        queue = Shoryuken::Client.queues(job.queue_name)
        queue.send_message(message(job, delay_seconds: delay))
      end

      private

      def message(job, options = {})
        body = job.serialize

        { message_body: body,
          message_attributes: message_attributes }.merge(options)
      end

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

      class JobWrapper #:nodoc:
        include Shoryuken::Worker

        shoryuken_options body_parser: :json, auto_delete: true

        def perform(sqs_msg, hash)
          approximate_receive_count = sqs_msg.approximate_receive_count
          if approximate_receive_count > 1
            max_receive_count = Shoryuken.redrive_policy_registry.fetch(sqs_msg.queue_name_from_msg)
            if approximate_receive_count > max_receive_count
              hash['job_class'] = hash['job_class'].gsub('Worker', 'DlqWorker')
            end
          end

          Base.execute hash
        end
      end
    end
  end
end
