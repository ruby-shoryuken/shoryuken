module Shoryuken
  module ActiveJobExtensions
    module SQSSendMessageParametersAccessor
      extend ActiveSupport::Concern

      included do
        attr_accessor :sqs_send_message_parameters
      end
    end

    module SQSSendMessageParametersSupport
      def initialize(*arguments)
        super(*arguments)
        self.sqs_send_message_parameters = {}
      end

      def enqueue(options = {})
        sqs_send_message_parameters[:message_group_id] = options[:message_group_id] if options[:message_group_id]
        sqs_send_message_parameters[:message_deduplication_id] = options[:message_deduplication_id] if options[:message_deduplication_id]
        sqs_send_message_parameters[:message_attributes] = options[:message_attributes] if options[:message_attributes]

        super
      end
    end
  end
end

ActiveJob::Base.include Shoryuken::ActiveJobExtensions::SQSSendMessageParametersAccessor
ActiveJob::Base.prepend Shoryuken::ActiveJobExtensions::SQSSendMessageParametersSupport
