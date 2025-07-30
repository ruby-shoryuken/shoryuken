# frozen_string_literal: true

module Shoryuken
  InlineMessage = Struct.new(
    :body,
    :attributes,
    :md5_of_body,
    :md5_of_message_attributes,
    :message_attributes,
    :message_id,
    :receipt_handle,
    :delete,
    :queue_name
  )
end
