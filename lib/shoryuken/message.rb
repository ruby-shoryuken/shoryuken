# frozen_string_literal: true

module Shoryuken
  # Represents an SQS message received by a Shoryuken worker.
  # This class wraps the raw AWS SQS message data and provides convenient methods
  # for interacting with the message, including deletion and visibility timeout management.
  #
  # Message instances are automatically created by Shoryuken and passed to your
  # worker's `perform` method as the first argument.
  #
  # @example Basic worker with message handling
  #   class MyWorker
  #     include Shoryuken::Worker
  #     shoryuken_options queue: 'my_queue'
  #
  #     def perform(sqs_msg, body)
  #       puts "Processing message #{sqs_msg.message_id}"
  #       puts "Message body: #{body}"
  #       puts "Queue: #{sqs_msg.queue_name}"
  #
  #       # Process the message...
  #
  #       # Delete the message when done (if auto_delete is false)
  #       sqs_msg.delete unless auto_delete?
  #     end
  #   end
  #
  # @example Working with message attributes
  #   def perform(sqs_msg, body)
  #     # Access standard SQS attributes
  #     sender_id = sqs_msg.attributes['SenderId']
  #     sent_timestamp = sqs_msg.attributes['SentTimestamp']
  #
  #     # Access custom message attributes
  #     priority = sqs_msg.message_attributes['Priority']&.[]('StringValue')
  #     user_id = sqs_msg.message_attributes['UserId']&.[]('StringValue')
  #   end
  class Message
    extend Forwardable

    # @!method message_id
    #   Returns the unique SQS message ID.
    #   @return [String] The message ID assigned by SQS
    #
    # @!method receipt_handle
    #   Returns the receipt handle needed for deleting or modifying the message.
    #   @return [String] The receipt handle for this message
    #
    # @!method md5_of_body
    #   Returns the MD5 hash of the message body.
    #   @return [String] MD5 hash of the message body
    #
    # @!method body
    #   Returns the raw message body as received from SQS.
    #   @return [String] The raw message body
    #
    # @!method attributes
    #   Returns the SQS message attributes (system attributes).
    #   @return [Hash] System attributes like SenderId, SentTimestamp, etc.
    #
    # @!method md5_of_message_attributes
    #   Returns the MD5 hash of the message attributes.
    #   @return [String] MD5 hash of message attributes
    #
    # @!method message_attributes
    #   Returns custom message attributes set by the sender.
    #   @return [Hash] Custom message attributes with typed values
    def_delegators(:data,
                   :message_id,
                   :receipt_handle,
                   :md5_of_body,
                   :body,
                   :attributes,
                   :md5_of_message_attributes,
                   :message_attributes)

    # @return [Aws::SQS::Client] The SQS client used for message operations
    attr_accessor :client

    # @return [String] The URL of the SQS queue this message came from
    attr_accessor :queue_url

    # @return [String] The name of the queue this message came from
    attr_accessor :queue_name

    # @return [Aws::SQS::Types::Message] The raw SQS message data
    attr_accessor :data

    # Creates a new Message instance wrapping SQS message data.
    #
    # @param client [Aws::SQS::Client] The SQS client for message operations
    # @param queue [Shoryuken::Queue] The queue this message came from
    # @param data [Aws::SQS::Types::Message] The raw SQS message data
    # @api private
    def initialize(client, queue, data)
      self.client     = client
      self.data       = data
      self.queue_url  = queue.url
      self.queue_name = queue.name
    end

    # Deletes this message from the SQS queue.
    # Once deleted, the message will not be redelivered and cannot be retrieved again.
    # This is typically called after successful message processing when auto_delete is disabled.
    #
    # @return [Aws::SQS::Types::DeleteMessageResult] The deletion result
    # @raise [Aws::SQS::Errors::ServiceError] If the deletion fails
    def delete
      client.delete_message(
        queue_url: queue_url,
        receipt_handle: data.receipt_handle
      )
    end

    # Changes the visibility timeout of this message with additional options.
    # This allows you to hide the message from other consumers for a longer or shorter period.
    #
    # @param options [Hash] Options to pass to change_message_visibility
    # @option options [Integer] :visibility_timeout New visibility timeout in seconds
    # @return [Aws::SQS::Types::ChangeMessageVisibilityResult] The change result
    # @raise [Aws::SQS::Errors::ServiceError] If the change fails
    #
    # @example Extending visibility with additional options
    #   sqs_msg.change_visibility(visibility_timeout: 300)
    #
    # @see #visibility_timeout= For a simpler interface
    def change_visibility(options)
      client.change_message_visibility(
        options.merge(queue_url: queue_url, receipt_handle: data.receipt_handle)
      )
    end

    # Sets the visibility timeout for this message.
    # This is a convenience method for changing only the visibility timeout.
    #
    # @param timeout [Integer] New visibility timeout in seconds (0-43200)
    # @return [Aws::SQS::Types::ChangeMessageVisibilityResult] The change result
    # @raise [Aws::SQS::Errors::ServiceError] If the change fails
    #
    # @example Extending processing time
    #   def perform(sqs_msg, body)
    #     if complex_processing_needed?(body)
    #       sqs_msg.visibility_timeout = 1800  # 30 minutes
    #     end
    #
    #     process_message(body)
    #   end
    #
    # @example Making message immediately visible again
    #   sqs_msg.visibility_timeout = 0  # Make visible immediately
    def visibility_timeout=(timeout)
      client.change_message_visibility(
        queue_url: queue_url,
        receipt_handle: data.receipt_handle,
        visibility_timeout: timeout
      )
    end
  end
end
