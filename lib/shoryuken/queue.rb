module Shoryuken
  class Queue
    attr_accessor :name, :client, :url

    def initialize(client, name)
      self.name   = name
      self.client = client
      self.url    = client.get_queue_url(queue_name: name).queue_url
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
      Shoryuken.client_middleware.invoke(options) do
        client.send_message(sanitize_message_body(options.merge(queue_url: url)))
      end
    end

    def send_messages(options)
      client.send_message_batch(sanitize_message_body(options.merge(queue_url: url)))
    end

    def receive_messages(options)
      client.receive_message(options.merge(queue_url: url)).
        messages.
        map { |m| Message.new(client, url, m) }
    end

    private

    def sanitize_message_body(options)
      messages = options[:entries] || [options]

      messages.each do |m|
        body = m[:message_body]
        if body.is_a?(Hash)
          m[:message_body] = JSON.dump(body)
        elsif !body.is_a? String
          fail ArgumentError, "The message body must be a String and you passed a #{body.class}"
        end
      end

      options
    end
  end
end
