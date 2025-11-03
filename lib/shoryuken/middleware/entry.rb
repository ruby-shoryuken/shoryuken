# frozen_string_literal: true

module Shoryuken
  module Middleware
    class Entry
      attr_reader :klass

      def initialize(klass, *args)
        @klass = klass
        @args  = args
      end

      def make_new
        @klass.new(*@args)
      end
    end
  end
end
