module Shoryuken
  module HashExt
    module StringifyKeys
      def stringify_keys
        keys.each do |key|
          self[key.to_s] = delete(key)
        end
        self
      end
    end

    module SymbolizeKeys
      def symbolize_keys
        keys.each do |key|
          self[(key.to_sym rescue key) || key] = delete(key)
        end
        self
      end
    end

    module DeepSymbolizeKeys
      def deep_symbolize_keys
        keys.each do |key|
          value = delete(key)
          self[(key.to_sym rescue key) || key] = value

          value.deep_symbolize_keys if value.is_a? Hash
        end
        self
      end
    end
  end

  module StringExt
    module Constantize
      def constantize
        names = split('::')
        names.shift if names.empty? || names.first.empty?

        constant = Object
        names.each do |name|
          constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
        end
        constant
      end
    end
  end
end

begin
  require 'active_support/core_ext/hash/keys'
  require 'active_support/core_ext/hash/deep_merge'
rescue LoadError
end

class Hash
  include Shoryuken::HashExt::StringifyKeys unless method_defined?(:stringify_keys)
  include Shoryuken::HashExt::SymbolizeKeys unless method_defined?(:symbolize_keys)
  include Shoryuken::HashExt::DeepSymbolizeKeys unless method_defined?(:deep_symbolize_keys)
end

begin
  require 'active_support/core_ext/string/inflections'
rescue LoadError
end

class String
  include Shoryuken::StringExt::Constantize unless method_defined?(:constantize)
end
