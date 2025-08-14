# frozen_string_literal: true

module Shoryuken
  # A high-performance alternative to OpenStruct for representing SQS messages.
  #
  # InlineMessage is a Struct-based implementation that provides the same interface
  # as the previous OpenStruct-based message representation but with significantly
  # better performance characteristics. It contains all the essential attributes
  # needed to represent an Amazon SQS message within the Shoryuken framework.
  InlineMessage = Struct.new(
    :body,
    :attributes,
    :md5_of_body,
    :md5_of_message_attributes,
    :message_attributes,
    :message_id,
    :receipt_handle,
    :delete,
    :queue_name,
    keyword_init: true
  )
end
