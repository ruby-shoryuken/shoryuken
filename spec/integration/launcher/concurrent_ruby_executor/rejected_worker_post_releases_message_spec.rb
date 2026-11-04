# frozen_string_literal: true

# This spec tests that a concurrent-ruby executor still works as the
# launcher_executor now that Shoryuken does not depend on concurrent-ruby, and
# that its Concurrent::RejectedExecutionError still counts as a rejected post.
#
# The app brings concurrent-ruby itself. When the executor rejects a worker
# post, Manager#assign releases the fetched message (visibility timeout 0) and
# never processes it.

require 'concurrent'
require_relative '../rejected_worker_post'

setup_sqs

expect_rejected_worker_post_released(Concurrent::CachedThreadPool, Concurrent::RejectedExecutionError)
