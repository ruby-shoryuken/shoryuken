# frozen_string_literal: true

# This spec tests that the default WeightedRoundRobin polling strategy pauses
# an empty queue for the configured `delay` before it polls that queue again.
#
# Expected behavior:
# - A poll that finds no messages pauses the queue for `delay` seconds
# - The queue is not polled again until the pause has passed
# - After the pause the queue is polled again, without waiting much longer

require_relative 'empty_queue_pause'

setup_sqs

expect_empty_queue_pause(batch: false)
