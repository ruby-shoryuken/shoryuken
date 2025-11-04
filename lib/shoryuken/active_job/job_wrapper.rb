# frozen_string_literal: true

require 'active_job'
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

      # Processes an ActiveJob job from an SQS message.
      #
      # @param sqs_msg [Shoryuken::Message] The SQS message containing the job data
      # @param hash [Hash] The parsed job data from the message body
      def perform(sqs_msg, hash)
        receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
        past_receives = receive_count - 1
        ::ActiveJob::Base.execute hash.merge({ 'executions' => past_receives })
      end
    end
  end
end