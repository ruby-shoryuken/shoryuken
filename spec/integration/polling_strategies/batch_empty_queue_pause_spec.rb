# frozen_string_literal: true

# This spec tests that an empty queue whose worker uses `batch: true` is paused
# for the configured `delay` like a single-message queue.
#
# Expected behavior:
# - A batch poll that finds no messages pauses the queue for `delay` seconds
# - The queue is not polled again until the pause has passed
# - After the pause the queue is polled again, without waiting much longer
#
# Regression: #568 - empty queues were not paused in batch processing mode.

require_relative 'empty_queue_pause'

setup_sqs

expect_empty_queue_pause(batch: true)
