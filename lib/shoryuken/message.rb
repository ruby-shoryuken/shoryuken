module Shoryuken
  class Message
    extend Forwardable

    def_delegators(:data,
                   :message_id,
                   :receipt_handle,
                   :md5_of_body,
                   :body,
                   :attributes,
                   :md5_of_message_attributes,
                   :message_attributes)

    attr_accessor :client, :queue_url, :queue_name, :data

    def initialize(client, queue, data)
      self.client     = client
      self.data       = data
      self.queue_url  = queue.url
      self.queue_name = queue.name
    end

    def delete
      client.delete_message(
        queue_url: queue_url,
        receipt_handle: data.receipt_handle
      )
    end

    def change_visibility(options)
      client.change_message_visibility(
        options.merge(queue_url: queue_url, receipt_handle: data.receipt_handle)
      )
    end

    def visibility_timeout=(timeout)
      client.change_message_visibility(
        queue_url: queue_url,
        receipt_handle: data.receipt_handle,
        visibility_timeout: timeout
      )
    end
  end
end
