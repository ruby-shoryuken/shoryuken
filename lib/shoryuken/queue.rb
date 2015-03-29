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
      client.send_message(options.merge(queue_url: url))
    end

    def send_messages(options)
      client.send_message_batch(options.merge(queue_url: url))
    end

    def receive_messages(options)
      client.receive_message(options.merge(queue_url: url)).
        messages.
        map { |m| Message.new(client, url, m) }
    end
  end
end
