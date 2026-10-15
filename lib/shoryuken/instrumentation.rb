# frozen_string_literal: true

require_relative 'instrumentation/event'
require_relative 'instrumentation/notifications'
require_relative 'instrumentation/logger_listener'

module Shoryuken
  # Instrumentation module providing pub/sub event notifications.
  # Inspired by Karafka's instrumentation architecture.
  #
  # @example Subscribing to events
  #   Shoryuken.monitor.subscribe('message.processed') do |event|
  #     StatsD.timing('shoryuken.process_time', event.duration * 1000)
  #   end
  #
  module Instrumentation
  end
end
