module Shoryuken
  module Worker
    def self.included(base)
      base.extend(ClassMethods)
      base.shoryuken_class_attribute :shoryuken_options_hash
    end

    module ClassMethods
      def perform_async(body, options = {})
        Shoryuken.worker_executor.perform_async(self, body, options)
      end

      def perform_in(interval, body, options = {})
        Shoryuken.worker_executor.perform_in(self, interval, body, options)
      end

      alias_method :perform_at, :perform_in

      def server_middleware
        @_server_chain ||= Shoryuken.server_middleware.dup
        yield @_server_chain if block_given?
        @_server_chain
      end

      def shoryuken_options(opts = {})
        self.shoryuken_options_hash = get_shoryuken_options.merge((opts || {}).deep_stringify_keys)
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
        shoryuken_options_hash || Shoryuken.default_worker_options
      end

      def shoryuken_class_attribute(*attrs) # :nodoc:
        attrs.each do |name|
          singleton_class.instance_eval do
            undef_method(name) if method_defined?(name) || private_method_defined?(name)
          end
          define_singleton_method(name) { nil }

          ivar = "@#{name}"

          singleton_class.instance_eval do
            m = "#{name}="
            undef_method(m) if method_defined?(m) || private_method_defined?(m)
          end

          define_singleton_method("#{name}=") do |val|
            singleton_class.class_eval do
              undef_method(name) if method_defined?(name) || private_method_defined?(name)
              define_method(name) { val }
            end

            # singleton? backwards compatibility for ruby < 2.1
            singleton_klass = respond_to?(:singleton?) ? singleton? : self != ancestors.first

            if singleton_klass
              class_eval do
                undef_method(name) if method_defined?(name) || private_method_defined?(name)
                define_method(name) do
                  if instance_variable_defined? ivar
                    instance_variable_get ivar
                  else
                    singleton_class.send name
                  end
                end
              end
            end
            val
          end

          # instance reader
          undef_method(name) if method_defined?(name) || private_method_defined?(name)
          define_method(name) do
            if instance_variable_defined?(ivar)
              instance_variable_get ivar
            else
              self.class.public_send name
            end
          end

          # instance writer
          m = "#{name}="
          undef_method(m) if method_defined?(m) || private_method_defined?(m)
          attr_writer name
        end
      end

      private

      def normalize_worker_queue!
        queue = shoryuken_options_hash['queue']
        if queue.respond_to?(:call)
          queue = queue.call
          shoryuken_options_hash['queue'] = queue
        end

        case shoryuken_options_hash['queue']
        when Array
          shoryuken_options_hash['queue'].map!(&:to_s)
        when Symbol
          shoryuken_options_hash['queue'] = shoryuken_options_hash['queue'].to_s
        end

        [shoryuken_options_hash['queue']].flatten.compact.each(&method(:register_worker))
      end

      def register_worker(queue)
        Shoryuken.register_worker(queue, self)
      end
    end
  end
end
