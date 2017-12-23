require 'shoryuken/worker/default_executor'
require 'shoryuken/worker/inline_executor'

module Shoryuken
  module Worker
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def perform_async(body, options = {})
        DefaultExecutor.perform_async(self, body, options)
      end

      def perform_in(interval, body, options = {})
        DefaultExecutor.perform_in(self, interval, body, options)
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
        new_hash = {}
        hash.each { |key, value| new_hash[key.to_s] = value }
        new_hash
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
