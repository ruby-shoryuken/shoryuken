# frozen_string_literal: true

module Shoryuken
  module Contracts
    # Validates the options of a single processing group
    class Group < Base
      self.error_messages = load_error_messages('group')

      # Unset values fall back to the global options
      optional(:concurrency) { |value| value.nil? || (value.is_a?(Integer) && value.positive?) }
      optional(:delay) { |value| non_negative_number?(value) }
      optional(:polling_strategy) { |value| value.nil? || value.is_a?(String) || value.is_a?(Class) }
      optional(:queues) { |value| valid_queues?(value) }
    end
  end
end
