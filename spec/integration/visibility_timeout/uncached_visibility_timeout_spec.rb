# frozen_string_literal: true

# This spec tests that by default (cache_visibility_timeout off) Shoryuken reads the queue VisibilityTimeout from
# SQS for every message, so a change on the queue applies to the next job without a restart.
#
# Each job runs 2.5s with auto_visibility_timeout. AutoExtendVisibility reads it when a job starts and Timing after it
# ends. A job that runs past the visibility timeout logs an "exceeded the queue visibility timeout" warning.

require_relative 'cache_visibility_timeout'

setup_sqs

reads, extensions, log = process_across_visibility_timeout_change(cache: false)

assert_equal(4, reads, "the visibility timeout must be read twice per message, got #{reads} GetQueueAttributes calls")
assert(extensions['first'].any?, "'first' must be extended, got #{extensions}")
assert(extensions['first'].all?(2), "'first' must be extended by the old 2s, got #{extensions}")
assert(extensions['second'].any?, "'second' must be extended, got #{extensions}")
assert(extensions['second'].all?(4), "'second' must be extended by the new 4s, got #{extensions}")

warnings = log.scan(/exceeded the queue visibility timeout by \d+(?:\.\d+)? ms/)
assert_equal(1, warnings.size, "only 'first' (2.5s on a 2s visibility timeout) must warn, got: #{log}")
