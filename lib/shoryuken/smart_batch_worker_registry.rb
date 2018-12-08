# This worker registry assumes:
#
#  1. Queues can have batches of differing types of Workers in their payloads
#  2. Each batch has a single worker type
#
module Shoryuken
  class SmartBatchWorkerRegistry < DefaultWorkerRegistry
    def fetch_worker(queue, message)
      first_message = message.is_a?(Array) ? message.first : message
      worker_class = begin
        first_message.message_attributes.dig('shoryuken_class', :string_value).constantize
      rescue
        @workers[queue]
      end
      worker_class.new if worker_class
    end
  end
end
