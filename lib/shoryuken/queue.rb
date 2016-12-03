module Shoryuken
  class Queue
    FIFO_ATTR               = 'FifoQueue'
    MESSAGE_GROUP_ID        = 'ShoryukenMessage'
    VISIBILITY_TIMEOUT_ATTR = 'VisibilityTimeout'

    attr_accessor :name, :client, :url

    def initialize(client, name)
      self.name   = name
      self.client = client
      self.url    = client.get_queue_url(queue_name: name).queue_url
    rescue Aws::SQS::Errors::NonExistentQueue => e
      raise e, "The specified queue '#{name}' does not exist."
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

    def fifo?
      @_fifo ||= queue_attributes.attributes[FIFO_ATTR] == 'true'
    end

    private

    def queue_attributes
      # Note: Retrieving all queue attributes as requesting `FifoQueue` on non-FIFO queue raises error.
      # See issue: https://github.com/aws/aws-sdk-ruby/issues/1350
      client.get_queue_attributes(queue_url: url, attribute_names: ['All'])
    end

    def sanitize_messages!(options)
      if options.is_a?(Array)
        entries = options.map.with_index do |m, index|
          { id: index.to_s }.merge(m.is_a?(Hash) ? m : { message_body: m })
        end

        options = { entries: entries }
      end

      options[:entries].each(&method(:sanitize_message!))

      options
    end

    def add_fifo_attributes!(options)
      return unless fifo?

      options[:message_group_id]         ||= MESSAGE_GROUP_ID
      options[:message_deduplication_id] ||= Digest::SHA256.hexdigest(options[:message_body])

      options
    end

    def sanitize_message!(options)
      options = { message_body: options } if options.is_a?(String)

      if (body = options[:message_body]).is_a?(Hash)
        options[:message_body] = JSON.dump(body)
      end

      add_fifo_attributes!(options)
      validate_message!(options)

      options
    end

    def validate_message!(options)
      unless (body = options[:message_body]).is_a?(String)
        fail ArgumentError, "The message body must be a String and you passed a #{body.class}."
      end

      validate_fifo_message!(options)

      options
    end

    def validate_fifo_message!(options)
      return unless fifo?

      if options[:delay_seconds]
        fail ArgumentError, 'FIFO queues do not accept DelaySeconds arguments.'
      end
    end
  end
end
