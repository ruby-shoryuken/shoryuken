# frozen_string_literal: true

# This spec tests that INT (e.g. Ctrl+C) shuts `shoryuken start` down like TERM.
#
# Expected behavior: after INT the process logs the shutdown, exits with status 0
# within the configured `timeout` (plus a margin) without waiting for the busy
# worker, and the killed worker's message is not deleted, so it becomes visible
# again after the queue's visibility timeout.
#
# Regression: #5 - the process hung on INT instead of exiting.

require_relative 'hard_shutdown'

setup_sqs

expect_hard_shutdown('INT')
