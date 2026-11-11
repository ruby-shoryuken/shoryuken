# frozen_string_literal: true

# This spec tests that with cache_visibility_timeout on, Shoryuken reads the queue VisibilityTimeout from SQS once
# and keeps that value until restart.
#
# Each job runs 2.5s with auto_visibility_timeout. After the queue VisibilityTimeout changes from 2s to 4s, the next
# job is still extended by 2s and Timing still warns that it exceeded the 2s visibility timeout.

require_relative 'cache_visibility_timeout'

setup_sqs

reads, extensions, log = process_across_visibility_timeout_change(cache: true)

assert_equal(1, reads, "the visibility timeout must be read once, got #{reads} GetQueueAttributes calls")
assert(extensions['first'].any?, "'first' must be extended, got #{extensions}")
assert(extensions['second'].any?, "'second' must be extended, got #{extensions}")
assert(extensions.values.flatten.all?(2), "extensions must keep the cached 2s, got #{extensions}")
assert_equal(2, log.scan('exceeded the queue visibility timeout by').size, log)
