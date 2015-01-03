module Shoryuken
  module Util
    def watchdog(last_words)
      yield
    rescue => ex
      logger.error last_words
      logger.error ex
      logger.error ex.backtrace.join("\n")
    end

    def logger
      Shoryuken.logger
    end

    def elapsed(started_at)
      # elapsed in ms
      (Time.now - started_at) * 1000
    end

    def unparse_queues(queues)
      queues.inject({}) do |queue_and_weights, name|
        queue_and_weights[name] = queue_and_weights[name].to_i + 1
        queue_and_weights
      end.to_a
    end

    def worker_name(worker_class, sqs_msg)
      if defined?(::ActiveJob) \
          && !sqs_msg.is_a?(Array) \
          && sqs_msg.message_attributes['shoryuken_class'] \
          && sqs_msg.message_attributes['shoryuken_class'][:string_value] == ActiveJob::QueueAdapters::ShoryukenAdapter::JobWrapper.to_s

        "ActiveJob/#{body['job_class'].constantize}"
      else
        worker_class.to_s
      end
    end
  end
end
