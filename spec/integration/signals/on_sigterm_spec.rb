# frozen_string_literal: true

# This spec tests that TERM hard-shuts `shoryuken start` down within `timeout`
# while a worker is still busy, and that the in-flight message is kept.
#
# Expected behavior: after TERM the process exits with status 0 within the
# configured `timeout` (plus a margin), without waiting for the busy worker to
# finish. The killed worker's message is not deleted (auto_delete runs only
# after `perform` returns), so it becomes visible again after the queue's
# visibility timeout.
#
# Regression: #215 - a hard shutdown hung while some workers were busy
# (CHANGELOG v2.0.7, "Fix hard shutdown if there are some busy workers").

require_relative 'hard_shutdown'

setup_sqs

expect_hard_shutdown('TERM')
