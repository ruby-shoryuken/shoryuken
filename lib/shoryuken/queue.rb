module Shoryuken
  class Queue
    attr_accessor :name, :client, :url

    def initialize(client, name)
      self.name = name
      self.client = client
      begin
        self.url = client.get_queue_url(queue_name: name).queue_url
      rescue Aws::SQS::Errors::NonExistentQueue => e
        raise e, "The specified queue '#{name}' does not exist"
      end
    end

    def visibility_timeout
      queue_attributes.attributes[VISIBILITY_TIMEOUT_ATTR].to_i
    end

    def delete_messages(options)
      client.delete_message_batch(options.merge(queue_url: url))
    end

    def send_message(options)
      options = sanitize_message!(options).merge(queue_url: url)

      Shoryuken.client_middleware.invoke(options) do
        client.send_message(options)
      end
    end

    def send_messages(options)
      client.send_message_batch(sanitize_messages!(options).merge(queue_url: url))
    end

    def receive_messages(options)
      client.receive_message(options.merge(queue_url: url)).
        messages.
        map { |m| Message.new(client, self, m) }
    end

    # Returns whether this queue is a FIFO queue or not.
    # @return [TrueClass, FalseClass]
    def is_fifo?
      queue_attributes.attributes[FIFO_ATTRIBUTE] == 'true'
    end

    # Returns whether this queue has content based deduplication enabled or not.
    # @return [TrueClass, FalseClass]
    def has_content_deduplication?
      queue_attributes.attributes[CONTENT_DEDUP_ATTRIBUTE] == 'true'
    end

    private

    FIFO_ATTRIBUTE = 'FifoQueue'
    CONTENT_DEDUP_ATTRIBUTE = 'ContentBasedDeduplication'
    MESSAGE_GROUP_ID = 'ShoryukenMessage'
    VISIBILITY_TIMEOUT_ATTR = 'VisibilityTimeout'

    # @return [Aws::SQS::Types::GetQueueAttributesResult]
    def queue_attributes
      client.get_queue_attributes(queue_url: url, attribute_names: [FIFO_ATTRIBUTE, CONTENT_DEDUP_ATTRIBUTE, VISIBILITY_TIMEOUT_ATTR])
    end

    # Returns sanitized messages, raising ArgumentError if any of the message is invalid.
    def sanitize_messages!(options)
      options = case
                when options.is_a?(Array)
                  { entries: options.map.with_index do |m, index|
                    { id: index.to_s }.merge(m.is_a?(Hash) ? m : { message_body: m }).tap(&method(:add_fifo_attributes!))
                  end }
                when options.is_a?(Hash)
                  options[:entries].each(&method(:add_fifo_attributes!))
                  options
                end
      validate_messages!(options)
      options
    end

    # Modifies the supplied hash and adds the required FIFO message attributes based on the queue configuration.
    def add_fifo_attributes!(message_hash)
      return unless is_fifo?

      message_hash[:message_group_id] = MESSAGE_GROUP_ID
      message_hash[:message_deduplication_id] = SecureRandom.uuid unless has_content_deduplication?

      message_hash
    end

    def sanitize_message!(options)
      options = case
                when options.is_a?(String)
                  # send_message('message')
                  { message_body: options }
                when options.is_a?(Hash)
                  options
                end
      add_fifo_attributes! options
      validate_message!(options)
      options
    end

    def validate_messages!(options)
      options[:entries].map { |m| validate_message!(m) }
    end

    def validate_message!(options)
      body = options[:message_body]
      if body.is_a?(Hash)
        options[:message_body] = JSON.dump(body)
      elsif !body.is_a?(String)
        fail ArgumentError, "The message body must be a String and you passed a #{body.class}"
      end
      if is_fifo? && options[:delay_seconds].is_a?(Fixnum)
        fail ArgumentError, 'FIFO queues do not accept DelaySeconds arguments.'
      end
      if is_fifo? && options[:message_group_id].nil?
        fail ArgumentError, 'This queue is FIFO and no message_group_id was provided.'
      end
      if is_fifo? && !has_content_deduplication? && options[:message_deduplication_id].nil?
        fail ArgumentError, 'This queue is FIFO without ContentBasedDeduplication enabled, and no MessageDeduplicationId was supplied'
      end
      options
    end
  end
end
