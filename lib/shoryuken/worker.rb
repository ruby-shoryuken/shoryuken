module Shoryuken
  module Worker
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def perform_async(body, options = {})
        options[:message_attributes] ||= {}
        options[:message_attributes]['shoryuken_class'] = {
          string_value: self.to_s,
          data_type: 'String'
        }

        options[:message_body] = body

        queue = options.delete(:queue) || get_shoryuken_options['queue']

        Shoryuken::Client.queues(queue).send_message(options)
      end

      def perform_in(interval, body, options = {})
        interval = interval.to_f
        now = Time.now.to_f
        ts = (interval < 1_000_000_000 ? (now + interval).to_f : interval)

        delay = (ts - now).ceil

        raise 'The maximum allowed delay is 15 minutes' if delay > 15 * 60

        perform_async(body, options.merge(delay_seconds: delay))
      end

      alias_method :perform_at, :perform_in

      def server_middleware
        @server_chain ||= Shoryuken.server_middleware.dup
        yield @server_chain if block_given?
        @server_chain
      end

      def shoryuken_options(opts = {})
        @shoryuken_options = get_shoryuken_options.merge(stringify_keys(opts || {}))
        normalize_worker_queue!
      end

      def auto_visibility_timeout?
        !!get_shoryuken_options['auto_visibility_timeout']
      end

      def exponential_backoff?
        !!get_shoryuken_options['retry_intervals']
      end

      def auto_delete?
        !!(get_shoryuken_options['delete'] || get_shoryuken_options['auto_delete'])
      end

      def get_shoryuken_options # :nodoc:
        @shoryuken_options || Shoryuken.default_worker_options
      end

      def stringify_keys(hash) # :nodoc:
        hash.keys.each do |key|
          hash[key.to_s] = hash.delete(key)
        end
        hash
      end

      private

      def normalize_worker_queue!
        queue = @shoryuken_options['queue']
        if queue.respond_to?(:call)
          queue = queue.call
          @shoryuken_options['queue'] = queue
        end

        case @shoryuken_options['queue']
        when Array
          @shoryuken_options['queue'].map!(&:to_s)
        when Symbol
          @shoryuken_options['queue'] = @shoryuken_options['queue'].to_s
        end

        [@shoryuken_options['queue']].flatten.compact.each(&method(:register_worker))
      end

      def register_worker(queue)
        Shoryuken.register_worker(queue, self)
      end
    end
  end
end
