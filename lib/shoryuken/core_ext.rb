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

    module DeepStringifyKeys
      def deep_stringify_keys
        keys.each do |key|
          value = delete(key)
          self[key.to_s] = value

          value.deep_stringify_keys if value.is_a? Hash
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

module ArrayExt
  module InGroupsOf
    def in_groups_of(number, fill_with = nil, &block)
      if number.to_i <= 0
        raise ArgumentError,
              "Group size must be a positive integer, was #{number.inspect}"
      end

      if fill_with == false
        collection = self
      else
        # size % number gives how many extra we have;
        # subtracting from number gives how many to add;
        # modulo number ensures we don't add group of just fill.
        padding = (number - size % number) % number
        collection = dup.concat(Array.new(padding, fill_with))
      end

      if block_given?
        collection.each_slice(number, &block)
      else
        collection.each_slice(number).to_a
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
  include Shoryuken::HashExt::DeepStringifyKeys unless method_defined?(:deep_stringify_keys)
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

begin
  require 'active_support/core_ext/array/grouping'
rescue LoadError
end

class Array
  include Shoryuken::ArrayExt::InGroupsOf unless method_defined?(:in_groups_of)
end
