# frozen_string_literal: true

module Shoryuken
  module ActiveJob
    # Adds an accessor for SQS SendMessage parameters on ActiveJob jobs
    # (instances of ActiveJob::Base). Shoryuken ActiveJob queue adapters use
    # these parameters when enqueueing jobs; other adapters can ignore them.
    module SQSSendMessageParametersAccessor
      extend ActiveSupport::Concern

      included do
        # @!attribute [rw] sqs_send_message_parameters
        #   @return [Hash] the SQS send message parameters
        attr_accessor :sqs_send_message_parameters
      end
    end

    # Initializes SQS SendMessage parameters on instances of ActiveJob::Base
    # to the empty hash, and populates it whenever `#enqueue` is called, such
    # as when using ActiveJob::Base.set.
    module SQSSendMessageParametersSupport
      # Initializes a new ActiveJob instance with empty SQS parameters
      #
      # @param arguments [Array] the job arguments
      def initialize(*arguments)
        super(*arguments)
        self.sqs_send_message_parameters = {}
      end
      ruby2_keywords(:initialize) if respond_to?(:ruby2_keywords, true)

      # Enqueues the job with optional SQS-specific parameters
      #
      # @param options [Hash] enqueue options
      # @option options [Hash] :message_attributes custom SQS message attributes
      # @option options [Hash] :message_system_attributes system attributes
      # @option options [String] :message_deduplication_id FIFO deduplication ID
      # @option options [String] :message_group_id FIFO message group ID
      # @return [Object] the enqueue result
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

ActiveJob::Base.include Shoryuken::ActiveJob::SQSSendMessageParametersAccessor
ActiveJob::Base.prepend Shoryuken::ActiveJob::SQSSendMessageParametersSupport
