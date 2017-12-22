module Shoryuken
  module Worker
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def perform_async(body, options = {})
        body = JSON.dump(body) if body.is_a?(Hash)

        sqs_msg = OpenStruct.new(body: body)

        new.perform(sqs_msg, parse_body(sqs_msg))
      end

      def perform_in(interval, body, options = {})
        perform_async(body, options)
      end

      private

      # Extract to a class
      def parse_body(sqs_msg)
        body_parser = get_shoryuken_options['body_parser']

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
            # see https://github.com/phstc/shoryuken/pull/91
            # JSON.load
            body_parser.load(sqs_msg.body)
          end
        end
      end
    end
  end
end
