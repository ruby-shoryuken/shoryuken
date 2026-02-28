# frozen_string_literal: true

module Shoryuken
  # Processes SQS messages by invoking the appropriate worker.
  # Handles middleware chain execution and exception handling.
  class Processor
    include Util

    # @return [String] the queue name
    attr_reader :queue

    # @return [Aws::SQS::Types::Message, Array<Aws::SQS::Types::Message>] the message or batch
    attr_reader :sqs_msg

    # Processes a message from a queue
    #
    # @param queue [String] the queue name
    # @param sqs_msg [Aws::SQS::Types::Message, Array<Aws::SQS::Types::Message>] the message or batch
    # @return [Object] the result of the worker's perform method
    def self.process(queue, sqs_msg)
      new(queue, sqs_msg).process
    end

    # Initializes a new Processor
    #
    # @param queue [String] the queue name
    # @param sqs_msg [Aws::SQS::Types::Message, Array<Aws::SQS::Types::Message>] the message or batch
    def initialize(queue, sqs_msg)
      @queue   = queue
      @sqs_msg = sqs_msg
    end

    # Processes the message through the middleware chain and worker
    #
    # @return [Object] the result of the worker's perform method
    def process
      worker_perform = proc do
        return logger.error { "No worker found for #{queue}" } unless worker

        Shoryuken::Logging.with_context("#{worker_name(worker.class, sqs_msg, body)}/#{queue}/#{sqs_msg.message_id}") do
          Shoryuken.monitor.instrument('message.processed', message_payload) do
            worker.class.server_middleware.invoke(worker, queue, sqs_msg, body) do
              worker.perform(sqs_msg, body)
            end
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
      # Note: message.processed event is already published by instrument() with
      # :exception and :exception_object in the payload (ActiveSupport-compatible)
      Array(Shoryuken.exception_handlers).each { |handler| handler.call(e, queue, sqs_msg) }

      raise
    end

    private

    # Returns payload hash for instrumentation events
    #
    # @return [Hash] the payload for instrumentation
    def message_payload
      {
        queue: queue,
        message_id: sqs_msg.is_a?(Array) ? sqs_msg.map(&:message_id) : sqs_msg.message_id,
        worker: worker&.class&.name
      }
    end

    # Fetches the worker instance for processing
    #
    # @return [Object, nil] the worker instance or nil if not found
    def worker
      @_worker ||= Shoryuken.worker_registry.fetch_worker(queue, sqs_msg)
    end

    # Returns the worker class
    #
    # @return [Class] the worker class
    def worker_class
      worker.class
    end

    # Parses the message body or bodies for batch processing
    #
    # @return [Object, Array<Object>] the parsed body or array of bodies
    def body
      @_body ||= sqs_msg.is_a?(Array) ? sqs_msg.map(&method(:parse_body)) : parse_body(sqs_msg)
    end

    # Parses a single message body
    #
    # @param sqs_msg [Aws::SQS::Types::Message] the message to parse
    # @return [Object] the parsed message body
    def parse_body(sqs_msg)
      BodyParser.parse(worker_class, sqs_msg)
    end
  end
end
