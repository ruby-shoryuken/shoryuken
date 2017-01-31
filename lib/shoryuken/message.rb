module Shoryuken
  class Message
    attr_accessor :client, :queue_url, :queue_name, :data

    def initialize(client, queue, data)
      self.client = client
      self.data = data

      if queue.is_a?(Shoryuken::Queue)
        self.queue_url = queue.url
        self.queue_name = queue.name
      else
        # TODO: Remove next major release
        Shoryuken.logger.warn do
          '[DEPRECATION] Passing a queue url into Shoryuken::Message is deprecated, please pass the queue itself'
        end
        self.queue_url = queue
      end
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

    def message_id
      data.message_id
    end

    def receipt_handle
      data.receipt_handle
    end

    def md5_of_body
      data.md5_of_body
    end

    def body
      data.body
    end

    def attributes
      data.attributes
    end

    def md5_of_message_attributes
      data.md5_of_message_attributes
    end

    def message_attributes
      data.message_attributes
    end

    def approximate_receive_count
      data.attributes['ApproximateReceiveCount'].to_i
    end

    def redelivery?
      approximate_receive_count > 1
    end

    def queue_name_from_msg
      JSON.parse(data.body)['queue_name']
    end
  end
end
