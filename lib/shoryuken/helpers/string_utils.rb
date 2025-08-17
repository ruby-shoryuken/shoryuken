# frozen_string_literal: true

module Shoryuken
  module Helpers
    # Utility methods for string manipulation.
    #
    # This module provides helper methods for common string operations that were
    # previously implemented as core class extensions. By using a dedicated
    # helper module, we avoid polluting the global namespace while maintaining
    # the same functionality.
    #
    # @example Basic usage
    #   klass = Shoryuken::Helpers::StringUtils.constantize('MyWorker')
    #   # => MyWorker
    module StringUtils
      class << self
        # Converts a string to a constant.
        #
        # This method takes a string representation of a constant name and returns
        # the actual constant. It handles nested constants (e.g., 'Foo::Bar') and
        # leading double colons (e.g., '::Object'). This is commonly used for
        # dynamically loading worker classes from configuration.
        #
        # @param string [String] The string to convert to a constant
        # @return [Class, Module] The constant represented by the string
        # @raise [NameError] if the constant is not found or not defined
        #
        # @example Converting a simple class name
        #   StringUtils.constantize('String')
        #   # => String
        #
        # @example Converting a nested constant
        #   StringUtils.constantize('Shoryuken::Worker')
        #   # => Shoryuken::Worker
        #
        # @example Handling leading double colon
        #   StringUtils.constantize('::Object')
        #   # => Object
        #
        # @example Worker class loading
        #   worker_class = StringUtils.constantize('MyApp::EmailWorker')
        #   worker_instance = worker_class.new
        #
        # @example Error handling
        #   begin
        #     StringUtils.constantize('NonExistentClass')
        #   rescue NameError => e
        #     puts "Class not found: #{e.message}"
        #   end
        def constantize(string)
          names = string.split('::')
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
end
