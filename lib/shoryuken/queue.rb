module Shoryuken
  class Queue
    attr_accessor :name, :client, :url

    def initialize(client, name)
      self.name   = name
      self.client = client
      begin
        self.url = client.get_queue_url(queue_name: name).queue_url
      rescue Aws::SQS::Errors::NonExistentQueue => e
        raise e, "The specified queue '#{name}' does not exist"
      end
    end

    def visibility_timeout
      client.get_queue_attributes(
        queue_url: url,
        attribute_names: ['VisibilityTimeout']
      ).attributes['VisibilityTimeout'].to_i
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

    private

    def sanitize_messages!(options)
      options = case
                when options.is_a?(Array)
                  { entries: options.map.with_index do |m, index|
                    { id: index.to_s }.merge(m.is_a?(Hash) ? m : { message_body: m })
                  end }
                when options.is_a?(Hash)
                  options
                end

      validate_messages!(options)

      options
    end

    def sanitize_message!(options)
      options = case
                when options.is_a?(String)
                  # send_message('message')
                  { message_body: options }
                when options.is_a?(Hash)
                  options
                end

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

      options
    end
  end
end
