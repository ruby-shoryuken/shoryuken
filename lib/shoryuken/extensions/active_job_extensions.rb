# frozen_string_literal: true

module Shoryuken
  module ActiveJobExtensions
    # Adds an accessor for SQS SendMessage parameters on ActiveJob jobs
    # (instances of ActiveJob::Base). Shoryuken ActiveJob queue adapters use
    # these parameters when enqueueing jobs; other adapters can ignore them.
    module SQSSendMessageParametersAccessor
      extend ActiveSupport::Concern

      included do
        attr_accessor :sqs_send_message_parameters
      end
    end

    # Initializes SQS SendMessage parameters on instances of ActiveJob::Base
    # to the empty hash, and populates it whenever `#enqueue` is called, such
    # as when using ActiveJob::Base.set.
    module SQSSendMessageParametersSupport
      def initialize(*arguments)
        super(*arguments)
        self.sqs_send_message_parameters = {}
      end
      ruby2_keywords(:initialize) if respond_to?(:ruby2_keywords, true)

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
