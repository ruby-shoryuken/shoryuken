require 'forwardable'

module Shoryuken
  class ReceivedMessage
    extend Forwardable

    # The queue from which this message was received.
    attr_reader :queue

    def initialize queue, struct
      @queue = queue
      @struct = struct
    end

    def_delegators :@struct, :attributes,
      # The ID of the message.
      :message_id,

      # A string associated with this specific instance of receiving this message.
      :receipt_handle,

      # The message's contents.
      :body,

      # An MD5 digest of the message body.
      :md5_of_body,

      # The message attributes attached to the message.
      :message_attributes,

      # An MD5 digest of the message body.
      :md5_of_message_attributes

    private :attributes

    # The AWS account number (or the IP address, if anonymous access is allowed) of the sender.
    def sender_id
      @sender_id ||= attributes["SenderId"]
    end

    # The time when the message was sent.
    def sent_at
      @sent_at ||=
        (timestamp = attributes["SentTimestamp"] and
         Time.at(timestamp.to_i / 1000.0)) || nil
    end

    # The number of times a message has been received but not deleted.
    def approximate_receive_count
      @receive_count ||=
        (count = attributes["ApproximateReceiveCount"] and
         count.to_i) or nil
    end

    # The time when the message was first received.
    def approximate_first_receive_at
      @first_receive_at ||=
        (timestamp = attributes["ApproximateFirstReceiveTimestamp"] and
         Time.at(timestamp.to_i / 1000.0)) || nil
    end
  end
end
