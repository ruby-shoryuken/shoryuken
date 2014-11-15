require 'json'

module Shoryuken
  class Processor
    include Celluloid
    include Util

    def initialize(manager)
      @manager = manager
    end

    def process(queue, sqs_msg)
      worker = Shoryuken.worker_loader.call(queue, sqs_msg)

      defer do
        body = get_body(worker.class, sqs_msg)

        Shoryuken.server_middleware.invoke(worker, queue, sqs_msg, body) do
          worker.perform(sqs_msg, body)
        end
      end

      @manager.async.processor_done(queue, current_actor)
    end

    private

    def get_body(worker_class, sqs_msg)
      if sqs_msg.is_a? Array
        sqs_msg.map { |m| parse_body(worker_class, m) }
      else
        parse_body(worker_class, sqs_msg)
      end
    end

    def parse_body(worker_class, sqs_msg)
      body_parser = worker_class.get_shoryuken_options['body_parser']

      case body_parser
      when :json
        JSON.parse(sqs_msg.body)
      when Proc
        body_parser.call(sqs_msg)
      when :text, nil
        sqs_msg.body
      else
        body_parser.parse(sqs_msg.body) if body_parser.respond_to?(:parse) # i.e. JSON.parse(...)
      end
    rescue => e
      logger.error "Error parsing the message body: #{e.message}\nbody_parser: #{body_parser}\nsqs_msg.body: #{sqs_msg.body}"
      nil
    end
  end
end
