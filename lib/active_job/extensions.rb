# frozen_string_literal: true

module Shoryuken
  module ActiveJob
    # Adds an accessor for SQS SendMessage parameters on ActiveJob jobs (instances of ActiveJob::Base). Shoryuken ActiveJob
    # queue adapters use these parameters when enqueueing jobs; other adapters can ignore them.
    module SQSSendMessageParametersAccessor
      extend ActiveSupport::Concern

      included do
        # @return [Hash] the SQS send message parameters
        attr_accessor :sqs_send_message_parameters
      end
    end

    # Initializes SQS SendMessage parameters on instances of ActiveJob::Base to the empty hash, and populates it whenever
    # `#enqueue` is called, such as when using ActiveJob::Base.set.
    module SQSSendMessageParametersSupport
      # Key of the job data entry that carries the SQS parameters of a received message to the deserialized job. It is
      # never part of the message body.
      JOB_DATA_KEY = 'shoryuken_sqs_send_message_parameters'

      # Initializes a new ActiveJob instance with empty SQS parameters
      #
      # Uses argument forwarding (...) to properly pass all arguments including keyword arguments to the base class.
      def initialize(...)
        super(...)
        self.sqs_send_message_parameters = {}
      end

      # Restores the job and the SQS parameters of the message it was received from (see
      # Shoryuken::ActiveJob::JobWrapper#perform), so re-enqueueing it from the worker keeps them
      #
      # @param job_data [Hash] the job data
      # @return [Object] the deserialize result
      def deserialize(job_data)
        result = super
        params = job_data[JOB_DATA_KEY]
        sqs_send_message_parameters.merge!(params) if params
        result
      end

      # Enqueues the job with optional SQS-specific parameters
      #
      # @param options [Hash] enqueue options
      # @option options [Hash] :message_attributes custom SQS message attributes
      # @option options [Hash] :message_system_attributes system attributes
      # @option options [String] :message_deduplication_id FIFO deduplication ID
      # @option options [String] :message_group_id FIFO message group ID
      # @return [Object] the enqueue result
      def enqueue(options = {})
        sqs_options = options.extract!(
          :message_attributes,
          :message_system_attributes,
          :message_deduplication_id,
          :message_group_id
        )
        sqs_send_message_parameters.merge! sqs_options

        super
      end
    end
  end
end

ActiveJob::Base.include Shoryuken::ActiveJob::SQSSendMessageParametersAccessor
ActiveJob::Base.prepend Shoryuken::ActiveJob::SQSSendMessageParametersSupport
