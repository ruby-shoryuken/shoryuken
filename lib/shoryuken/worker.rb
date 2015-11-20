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

      # TODO: Shoryuken options should not invoke side effects.
      # The method makes it sound like it just sets configuration, but it performs
      # real logic.
      def shoryuken_options(opts = {})
        @shoryuken_options = get_shoryuken_options.merge(stringify_keys(opts || {}))

        queues = (@shoryuken_options['queues'] ||= [])

        if @shoryuken_options['queue']
          Shoryuken.logger.warn '[DEPRECATION] queue is deprecated as an option in favor of multiple queue support, please use queues instead'

          queues << @shoryuken_options['queue']
          @shoryuken_options['queue'] = nil
        end

        # FIXME: We shouldn't mutate user supplied values.
        # Currently done to preserve behavior when a queue is a proc, which probably
        # shouldn't be supported.
        @shoryuken_options['queues'] = Shoryuken::QueueRegistration.new(self).register_queues!(queues)
      end


      def auto_visibility_timeout?
        !!get_shoryuken_options['auto_visibility_timeout']
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
    end
  end
end
