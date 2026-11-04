# frozen_string_literal: true

# This spec tests that a fetched message whose worker post is rejected by the
# executor is released (visibility timeout 0) instead of being left in flight.
#
# When the launcher executor rejects the worker post (it was shut down between
# the running? check and the post, or a bounded custom launcher_executor is
# saturated), Manager#assign rolls back its busy counter and skips the message.
# It used to just drop the message, so it stayed invisible on SQS for the whole
# queue visibility timeout before any consumer could receive it.
#
# The rejected message is made visible again at once, and it
# is never processed.
#
# Regression: the message stayed in flight for the full visibility timeout.

require_relative 'rejected_worker_post'

setup_sqs

executor = rejecting_executor(Shoryuken::Helpers::ThreadPool, Shoryuken::Errors::RejectedExecutionError)
Shoryuken.define_singleton_method(:launcher_executor) { executor }

expect_rejected_worker_post_released
