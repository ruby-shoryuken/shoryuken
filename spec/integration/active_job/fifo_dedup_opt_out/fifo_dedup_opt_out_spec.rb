# frozen_string_literal: true

require 'digest'

# This spec tests opting out of the automatic FIFO message_deduplication_id that
# the ActiveJob adapter generates.
#
# For FIFO queues the adapter derives a content-based message_deduplication_id
# from the serialized job minus job_id/enqueued_at (see issues #457 / #750). That
# means two *distinct* enqueues of the same job class + args within SQS's 5-minute
# window collapse into one - the second is silently dropped. That is intentional,
# but it is a "skipped message" trap for users who legitimately enqueue the same
# work twice.
#
# Expected behavior: setting Shoryuken.active_job_fifo_message_deduplication = false
# stops the adapter from generating the id, so those enqueues are no longer
# silently deduplicated. The default (true) preserves the existing behavior.
#
# Regression: there was no way to disable the auto-generated deduplication id.

setup_active_job

class FifoOptOutJob < ActiveJob::Base
  queue_as :fifo_opt_out

  def perform(_arg); end
end

fifo_queue_mock = Object.new
fifo_queue_mock.define_singleton_method(:fifo?) { true }
fifo_queue_mock.define_singleton_method(:name) { 'fifo_opt_out.fifo' }

captured = nil
fifo_queue_mock.define_singleton_method(:send_message) { |params| captured = params }

Shoryuken::Client.define_singleton_method(:queues) { |_queue_name = nil| fifo_queue_mock }
Shoryuken.define_singleton_method(:register_worker) { |*| nil }

# Default behavior: the adapter sets a content-based dedup id (excluding the
# per-enqueue job_id/enqueued_at), so two identical jobs would collapse to one.
FifoOptOutJob.perform_later('same-args')

assert(
  captured.key?(:message_deduplication_id),
  'by default a FIFO ActiveJob send gets an auto-generated message_deduplication_id'
)

body = captured[:message_body]
expected = Digest::SHA256.hexdigest(JSON.dump(body.except('job_id', 'enqueued_at')))
assert_equal(expected, captured[:message_deduplication_id])

# Opt-out: with deduplication disabled the adapter no longer sets a dedup id, so
# distinct enqueues of identical jobs are not silently dropped.
Shoryuken.active_job_fifo_message_deduplication = false
captured = nil
FifoOptOutJob.perform_later('same-args')

refute(
  captured.key?(:message_deduplication_id),
  'with deduplication disabled the adapter must not set message_deduplication_id'
)

# An explicit deduplication id must still be honored even when auto-generation is off.
captured = nil
FifoOptOutJob.set(message_deduplication_id: 'explicit-id').perform_later('same-args')

assert_equal('explicit-id', captured[:message_deduplication_id])
