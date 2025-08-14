# frozen_string_literal: true

module Shoryuken
  class Client
    @@queues = {}

    class << self
      def queues(name)
        @@queues[name.to_s] ||= Shoryuken::Queue.new(sqs, name)
      end

      def sqs
        Shoryuken.sqs_client
      end

      def sqs=(sqs)
        # Since the @@queues values (Shoryuken::Queue objects) are built referencing @@sqs, if it changes, we need to
        #   re-build them on subsequent calls to `.queues(name)`.
        @@queues = {}

        Shoryuken.sqs_client = sqs
      end
    end
  end
end
