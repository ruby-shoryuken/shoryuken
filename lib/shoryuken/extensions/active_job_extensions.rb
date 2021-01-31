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
        sqs_options = options.extract! :message_attributes,
                                       :message_system_attributes,
                                       :message_deduplication_id,
                                       :message_group_id
        sqs_send_message_parameters.merge! sqs_options

        super
      end
    end
  end
end

ActiveJob::Base.include Shoryuken::ActiveJobExtensions::SQSSendMessageParametersAccessor
ActiveJob::Base.prepend Shoryuken::ActiveJobExtensions::SQSSendMessageParametersSupport
