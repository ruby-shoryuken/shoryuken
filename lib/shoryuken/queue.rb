module Shoryuken
  class Queue
    def initialize(name, sqs)
      @name, @sqs = name, sqs
    end

    def arn
      attributes['QueueArn']
    end

    def extend_invisibility(received_message, extension)
      @sqs.change_message_visibility(
        queue_url: url,
        receipt_handle: received_message.receipt_handle,
        visibility_timeout: extension)
    end

    def receive_messages(options = {})
      @sqs.receive_message(options.merge(queue_url: url))
          .messages
          .map { |struct| ReceivedMessage.new(@name, struct) }
    end

    def send_message(body, options = {})
      body = JSON.dump(body) if body.is_a?(Hash)

      @sqs.send_message(options.merge(queue_url: url, message_body: body))
    end

    def url
      @url ||= @sqs.get_queue_url(queue_name: @name).queue_url
    end

    def visibility_timeout
      @visibility_timeout ||= attributes['VisibilityTimeout'].to_i
    end

    private

    def attributes
      @attributes ||= @sqs.get_queue_attributes(queue_url: url, attribute_names: %w(All)).attributes
    end
  end
end
