# frozen_string_literal: true

module Shoryuken
  # Namespace for all Shoryuken-specific errors.
  # These provide more meaningful error types than generic Ruby exceptions,
  # making it easier to rescue and handle specific failure cases.
  module Errors
    # Base class for all Shoryuken errors
    class BaseError < StandardError; end

    # Raised when there is a configuration validation failure
    class InvalidConfigurationError < BaseError; end

    # Raised when a specified SQS queue does not exist or cannot be accessed
    class QueueNotFoundError < BaseError; end

    # Raised when worker registration fails due to conflicts
    # (e.g., registering multiple workers for a batch queue)
    class InvalidWorkerRegistrationError < BaseError; end

    # Raised when an invalid polling strategy is specified
    class InvalidPollingStrategyError < BaseError; end

    # Raised when an invalid lifecycle event name is used
    class InvalidEventError < BaseError; end

    # Raised when a delay exceeds the maximum allowed by SQS (15 minutes)
    class InvalidDelayError < BaseError; end

    # Raised when an ARN format is invalid
    class InvalidArnError < BaseError; end

    # Exception raised to trigger graceful shutdown of the server
    # @see https://github.com/mperham/sidekiq/blob/33f5d6b2b6c0dfaab11e5d39688cab7ebadc83ae/lib/sidekiq/cli.rb#L20
    class Shutdown < Interrupt; end
  end
end
