# frozen_string_literal: true

module Shoryuken
  class Processor
    include Util

    attr_reader :queue, :sqs_msg

    def self.process(queue, sqs_msg)
      new(queue, sqs_msg).process
    end

    def initialize(queue, sqs_msg)
      @queue   = queue
      @sqs_msg = sqs_msg
    end

    def process
      worker_perform = proc do
        return logger.error { "No worker found for #{queue}" } unless worker

        Shoryuken::Logging.with_context("#{worker_name(worker.class, sqs_msg, body)}/#{queue}/#{sqs_msg.message_id}") do
          worker.class.server_middleware.invoke(worker, queue, sqs_msg, body) do
            worker.perform(sqs_msg, body)
          end
        end
      end

      if Shoryuken.enable_reloading
        Shoryuken.reloader.call do
          worker_perform.call
        end
      else
        worker_perform.call
      end
    rescue Exception => e
      Array(Shoryuken.exception_handlers).each { |handler| handler.call(e, queue, sqs_msg) }

      raise
    end

    private

    def worker
      @_worker ||= Shoryuken.worker_registry.fetch_worker(queue, sqs_msg)
    end

    def worker_class
      worker.class
    end

    def body
      @_body ||= sqs_msg.is_a?(Array) ? sqs_msg.map(&method(:parse_body)) : parse_body(sqs_msg)
    end

    def parse_body(sqs_msg)
      BodyParser.parse(worker_class, sqs_msg)
    end
  end
end
