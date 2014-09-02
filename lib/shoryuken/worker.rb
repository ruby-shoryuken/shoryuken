module Shoryuken
  module Worker
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def perform_async(*args)
        Shoryuken::Client.push('class' => self, 'args' => args)
      end

      def shoryuken_options(opts = {})
        @shoryuken_options = get_shoryuken_options.merge(stringify_keys(opts || {}))
      end

      def get_shoryuken_options # :nodoc:
        @shoryuken_options || { 'queue' => 'default' }
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
