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

      def enqueue(job, options = {}) #:nodoc:
        register_worker!(job)

        queue = Shoryuken::Client.queues(job.queue_name)
        queue.send_message(message(queue, job, options))
      end

      def enqueue_at(job, timestamp) #:nodoc:
        enqueue(job, delay_seconds: calculate_delay(timestamp))
      end

      private

      def calculate_delay(timestamp)
        delay = (timestamp - Time.current.to_f).round
        raise 'The maximum allowed delay is 15 minutes' if delay > 15.minutes

        delay
      end

      def message(queue, job, options = {})
        body = job.serialize

        attributes = options.delete(:message_attributes) || {}

        msg = {
          message_body: body,
          message_attributes: attributes.merge(MESSAGE_ATTRIBUTES)
        }

        if queue.fifo?
          # See https://github.com/phstc/shoryuken/issues/457
          msg[:message_deduplication_id] = Digest::SHA256.hexdigest(JSON.dump(body.except('job_id')))
        end

        msg.merge(options)
      end

      def register_worker!(job)
        Shoryuken.register_worker(job.queue_name, JobWrapper)
      end

      class JobWrapper #:nodoc:
        include Shoryuken::Worker

        shoryuken_options body_parser: :json, auto_delete: true

        def perform(_sqs_msg, hash)
          Base.execute hash
        end
      end

      MESSAGE_ATTRIBUTES = {
        'shoryuken_class' => {
          string_value: JobWrapper.to_s,
          data_type: 'String'
        }
      }.freeze
    end
  end
end
