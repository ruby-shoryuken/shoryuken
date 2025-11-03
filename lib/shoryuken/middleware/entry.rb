# frozen_string_literal: true

module Shoryuken
  module Middleware
    # Represents an entry in a middleware chain, storing the middleware class
    # and any arguments needed for its instantiation.
    #
    # @api private
    class Entry
      # @return [Class] The middleware class this entry represents
      attr_reader :klass

      # Creates a new middleware entry.
      #
      # @param klass [Class] The middleware class
      # @param args [Array] Arguments to pass to the middleware constructor
      def initialize(klass, *args)
        @klass = klass
        @args  = args
      end

      # Creates a new instance of the middleware class with the stored arguments.
      #
      # @return [Object] A new instance of the middleware class
      def make_new
        @klass.new(*@args)
      end
    end
  end
end
