# frozen_string_literal: true

module Shoryuken
  module Util
    def logger
      Shoryuken.logger
    end

    def fire_event(event, reverse = false, event_options = {})
      logger.debug { "Firing '#{event}' lifecycle event" }
      arr = Shoryuken.options[:lifecycle_events][event]
      arr.reverse! if reverse
      arr.each do |block|
        block.call(event_options)
      rescue => e
        logger.warn(event: event)
        logger.warn "#{e.class.name}: #{e.message}"
      end
    end

    def elapsed(started_at)
      # elapsed in ms
      (Time.now - started_at) * 1000
    end

    def unparse_queues(queues)
      queues.each_with_object({}) do |name, queue_and_weights|
        queue_and_weights[name] = queue_and_weights[name].to_i + 1
      end.to_a
    end

    def worker_name(worker_class, sqs_msg, body = nil)
      if Shoryuken.active_job? \
          && !sqs_msg.is_a?(Array) \
          && sqs_msg.message_attributes \
          && sqs_msg.message_attributes['shoryuken_class'] \
          && sqs_msg.message_attributes['shoryuken_class'][:string_value] \
          == ActiveJob::QueueAdapters::ShoryukenAdapter::JobWrapper.to_s \
          && body

        "ActiveJob/#{body['job_class']}"
      else
        worker_class.to_s
      end
    end
  end
end
