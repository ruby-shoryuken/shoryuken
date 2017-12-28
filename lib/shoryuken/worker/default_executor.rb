module Shoryuken
  module Worker
    class DefaultExecutor
      class << self
        def perform_async(worker_class, body, options = {})
          options[:message_attributes] ||= {}
          options[:message_attributes]['shoryuken_class'] = {
            string_value: worker_class.to_s,
            data_type: 'String'
          }

          options[:message_body] = body

          queue = options.delete(:queue) || worker_class.get_shoryuken_options['queue']

          Shoryuken::Client.queues(queue).send_message(options)
        end

        def perform_in(worker_class, interval, body, options = {})
          interval = interval.to_f
          now = Time.now.to_f
          ts = (interval < 1_000_000_000 ? (now + interval).to_f : interval)

          delay = (ts - now).ceil

          raise 'The maximum allowed delay is 15 minutes' if delay > 15 * 60

          worker_class.perform_async(body, options.merge(delay_seconds: delay))
        end
      end
    end
  end
end
