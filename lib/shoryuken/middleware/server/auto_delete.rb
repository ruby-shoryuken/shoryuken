# frozen_string_literal: true

module Shoryuken
  module Middleware
    module Server
      # Middleware that automatically deletes messages after successful processing.
      # Only deletes messages when the worker has auto_delete enabled.
      class AutoDelete
        # Processes a message and deletes it if auto_delete is enabled
        #
        # @param worker [Object] the worker instance
        # @param queue [String] the queue name
        # @param sqs_msg [Shoryuken::Message, Array<Shoryuken::Message>] the message or batch
        # @param _body [Object] the parsed message body (unused)
        # @yield continues to the next middleware in the chain
        # @return [void]
        def call(worker, queue, sqs_msg, _body)
          yield

          return unless worker.class.auto_delete?

          entries = [sqs_msg].flatten.map.with_index { |message, i| { id: i.to_s, receipt_handle: message.receipt_handle } }

          Shoryuken::Client.queues(queue).delete_messages(entries: entries)
        end
      end
    end
  end
end
