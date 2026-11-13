# frozen_string_literal: true

require 'active_job'
require 'active_job/extensions'
require 'shoryuken/worker'

module Shoryuken
  module ActiveJob
    # Internal worker class that processes ActiveJob jobs.
    # This class bridges ActiveJob's interface with Shoryuken's worker interface.
    #
    # @api private
    class JobWrapper # :nodoc:
      include Shoryuken::Worker

      shoryuken_options body_parser: :json, auto_delete: true

      # Message attributes the adapters set themselves
      ADAPTER_MESSAGE_ATTRIBUTES = %w[shoryuken_class].freeze

      private_constant :ADAPTER_MESSAGE_ATTRIBUTES

      # Processes an ActiveJob job from an SQS message. SQS redeliveries of the message count as executions on top
      # of the serialized ones. The message group id and the custom message attributes become the job's SQS
      # parameters, so a retry or a continuation resume keeps them.
      #
      # @param sqs_msg [Shoryuken::Message] The SQS message containing the job data
      # @param hash [Hash] The parsed job data from the message body
      def perform(sqs_msg, hash)
        receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
        past_receives = receive_count - 1
        job_data = hash.merge({ 'executions' => hash['executions'].to_i + past_receives })
        params = sqs_send_message_parameters(sqs_msg)
        job_data[SQSSendMessageParametersSupport::JOB_DATA_KEY] = params if params
        ::ActiveJob::Base.execute job_data
      end

      private

      # Builds the SQS parameters a re-enqueue of the job reuses: the message group id and the custom message
      # attributes. The deduplication id is left out, as SQS would drop a re-enqueue that reuses it.
      #
      # @param sqs_msg [Shoryuken::Message] the received SQS message
      # @return [Hash, nil] the parameters, nil when the message has none
      def sqs_send_message_parameters(sqs_msg)
        group_id = sqs_msg.attributes['MessageGroupId']
        params = { message_group_id: group_id } if group_id

        sqs_msg.message_attributes&.each do |name, value|
          next if ADAPTER_MESSAGE_ATTRIBUTES.include?(name)

          params ||= {}
          (params[:message_attributes] ||= {})[name] = value.to_h.slice(:data_type, :string_value, :binary_value)
        end

        params
      end
    end
  end
end
