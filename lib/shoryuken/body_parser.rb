# frozen_string_literal: true

module Shoryuken
  # Parses SQS message bodies according to worker configuration.
  # Supports JSON parsing, text extraction, custom Procs, and
  # any object that responds to parse or load methods.
  class BodyParser
    class << self
      # Parses the body of an SQS message according to the worker's body_parser option
      #
      # @param worker_class [Class] the worker class with shoryuken options
      # @param sqs_msg [Shoryuken::Message] the SQS message to parse
      # @return [Object] the parsed message body
      def parse(worker_class, sqs_msg)
        body_parser = worker_class.get_shoryuken_options['body_parser']

        case body_parser
        when :json
          JSON.parse(sqs_msg.body)
        when Proc
          body_parser.call(sqs_msg)
        when :text, nil
          sqs_msg.body
        else
          if body_parser.respond_to?(:parse)
            # JSON.parse
            body_parser.parse(sqs_msg.body)
          elsif body_parser.respond_to?(:load)
            # see https://github.com/ruby-shoryuken/shoryuken/pull/91
            # JSON.load
            body_parser.load(sqs_msg.body)
          end
        end
      end
    end
  end
end
