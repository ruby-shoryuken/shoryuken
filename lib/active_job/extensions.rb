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
      # Key of the job data entry that carries the received SQS message to the deserialized job. It is never part of
      # the message body.
      JOB_DATA_KEY = 'shoryuken_sqs_message'

      # Message attributes the adapters set themselves
      ADAPTER_MESSAGE_ATTRIBUTES = %w[shoryuken_class].freeze

      private_constant :ADAPTER_MESSAGE_ATTRIBUTES

      # Initializes a new ActiveJob instance with empty SQS parameters
      #
      # Uses argument forwarding (...) to properly pass all arguments including keyword arguments to the base class.
      def initialize(...)
        super(...)
        self.sqs_send_message_parameters = {}
      end

      # Restores the job and keeps the SQS message it was received from (see Shoryuken::ActiveJob::JobWrapper#perform)
      #
      # @param job_data [Hash] the job data
      # @return [Object] the deserialize result
      def deserialize(job_data)
        result = super
        @sqs_received_message = job_data[JOB_DATA_KEY]
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
        reuse_received_message_parameters
        sqs_send_message_parameters.merge! sqs_options

        super
      end

      private

      # Adds the group id and the custom message attributes of the message the job was received from to its SQS
      # parameters, so a retry or a continuation resume keeps them. Parameters already set win. The deduplication id is
      # left out, as SQS would drop a re-enqueue that reuses it.
      #
      # @return [void]
      def reuse_received_message_parameters
        sqs_msg = @sqs_received_message
        return unless sqs_msg

        @sqs_received_message = nil
        params = sqs_send_message_parameters

        group_id = sqs_msg.attributes['MessageGroupId']
        params[:message_group_id] = group_id if group_id && !params.key?(:message_group_id)

        attributes = received_message_attributes(sqs_msg)
        params[:message_attributes] = attributes.merge(params[:message_attributes] || {}) unless attributes.empty?
      end

      # Copies the custom message attributes of a received message in the form SendMessage takes
      #
      # @param sqs_msg [Shoryuken::Message] the received message
      # @return [Hash{String => Hash}] the attributes
      def received_message_attributes(sqs_msg)
        (sqs_msg.message_attributes || {}).each_with_object({}) do |(name, value), attributes|
          next if ADAPTER_MESSAGE_ATTRIBUTES.include?(name)

          attribute = { data_type: value[:data_type] }
          attribute[:string_value] = value[:string_value] if value[:string_value]
          attribute[:binary_value] = value[:binary_value] if value[:binary_value]
          attributes[name] = attribute
        end
      end
    end
  end
end

ActiveJob::Base.include Shoryuken::ActiveJob::SQSSendMessageParametersAccessor
ActiveJob::Base.prepend Shoryuken::ActiveJob::SQSSendMessageParametersSupport
