module Shoryuken
  class Queue
    include Util

    FIFO_ATTR               = 'FifoQueue'
    MESSAGE_GROUP_ID        = 'ShoryukenMessage'
    VISIBILITY_TIMEOUT_ATTR = 'VisibilityTimeout'

    attr_accessor :name, :client, :url

    def initialize(client, name_or_url)
      self.client = client
      set_name_and_url(name_or_url)
    end

    def visibility_timeout
      queue_attributes.attributes[VISIBILITY_TIMEOUT_ATTR].to_i
    end

    def delete_messages(options)
      client.delete_message_batch(
        options.merge(queue_url: url)
      ).failed.any? do |failure|
        logger.error do
          "Could not delete #{failure.id}, code: '#{failure.code}', message: '#{failure.message}', sender_fault: #{failure.sender_fault}"
        end
      end
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
      client.receive_message(options.merge(queue_url: url)).messages.map { |m| Message.new(client, self, m) }
    end

    def fifo?
      @_fifo ||= queue_attributes.attributes[FIFO_ATTR] == 'true'
    end

    private

    def set_name_and_url(name_or_url)
      if name_or_url.start_with?('https://sqs.')
        self.name = name_or_url.split('/').last
        self.url  = name_or_url
      else
        begin
          self.name = name_or_url
          self.url  = client.get_queue_url(queue_name: name_or_url).queue_url
        rescue Aws::SQS::Errors::NonExistentQueue => e
          raise e, "The specified queue '#{name}' does not exist."
        end
      end
    end

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
      options[:message_deduplication_id] ||= Digest::SHA256.hexdigest(options[:message_body].to_s)

      options
    end

    def sanitize_message!(options)
      options = { message_body: options } if options.is_a?(String)

      if (body = options[:message_body]).is_a?(Hash)
        options[:message_body] = JSON.dump(body)
      end

      add_fifo_attributes!(options)

      options
    end
  end
end
