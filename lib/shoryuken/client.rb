require 'multi_json'

module Shoryuken
  class Client
    def self.push(item)
      queue = queue_by_name(item['class'].shoryuken_options['queue'])

      payload = MultiJson.encode(item)

      queue.send_message(payload)
    end

    def self.queue_by_name(name)
      @queues ||= {}
      @queues[name.to_s] ||= sqs.queues.named(name)
    end

    def self.receive_message(queue, options = {})
      queue.receive_message(options)
    end

    def self.sqs
      @sqs ||= AWS::SQS.new
    end
  end
end
