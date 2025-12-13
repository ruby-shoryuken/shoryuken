# frozen_string_literal: true

module Shoryuken
  # Namespace for all Shoryuken-specific errors.
  # These provide more meaningful error types than generic Ruby exceptions,
  # making it easier to rescue and handle specific failure cases.
  module Errors
    # Base class for all Shoryuken errors
    BaseError = Class.new(StandardError)

    # Raised when there is a configuration validation failure
    InvalidConfigurationError = Class.new(BaseError)

    # Raised when a specified SQS queue does not exist or cannot be accessed
    QueueNotFoundError = Class.new(BaseError)

    # Raised when worker registration fails due to conflicts
    # (e.g., registering multiple workers for a batch queue)
    InvalidWorkerRegistrationError = Class.new(BaseError)

    # Raised when an invalid polling strategy is specified
    InvalidPollingStrategyError = Class.new(BaseError)

    # Raised when an invalid lifecycle event name is used
    InvalidEventError = Class.new(BaseError)

    # Raised when a delay exceeds the maximum allowed by SQS (15 minutes)
    InvalidDelayError = Class.new(BaseError)

    # Raised when an ARN format is invalid
    InvalidArnError = Class.new(BaseError)

    # Exception raised to trigger graceful shutdown of the server
    # @see https://github.com/mperham/sidekiq/blob/33f5d6b2b6c0dfaab11e5d39688cab7ebadc83ae/lib/sidekiq/cli.rb#L20
    Shutdown = Class.new(Interrupt)
  end
end
