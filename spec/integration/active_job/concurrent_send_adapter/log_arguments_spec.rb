# frozen_string_literal: true

# This spec tests that the default error handler of
# ShoryukenConcurrentSendAdapter honours ActiveJob `log_arguments`.
#
# It used to log `job.inspect` on a failed send, so the job arguments and the
# SQS message body reached the log even for a job with
# `self.log_arguments = false`.
#
# A failed send of a job with `log_arguments = false` logs its class, job id,
# queue and the error, but none of its arguments. A job that keeps the default
# `log_arguments = true` also gets its arguments in that line.

require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

setup_sqs
setup_active_job

log = StringIO.new
Shoryuken.logger = Logger.new(log)

class SecretArgumentsJob < ActiveJob::Base
  self.log_arguments = false

  def perform(_email, _token); end
end

class PlainArgumentsJob < ActiveJob::Base
  def perform(_email, _token); end
end

missing_queue = "missing-#{DT.uuid}"
adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new
ActiveJob::Base.queue_adapter = adapter

secret_job = SecretArgumentsJob.set(queue: missing_queue).perform_later('user@example.com', 'SECRET-TOKEN-123')
plain_job = PlainArgumentsJob.set(queue: missing_queue).perform_later('other@example.com', 'PLAIN-TOKEN-456')

assert(adapter.wait_for_pending_sends(15), 'both failed sends must count as finished')

secret_line = log.string.lines.find { |line| line.include?("Job ID: #{secret_job.job_id}") }
plain_line = log.string.lines.find { |line| line.include?("Job ID: #{plain_job.job_id}") }

assert(
  secret_line&.include?(
    "Failed to enqueue job: SecretArgumentsJob (Job ID: #{secret_job.job_id}) to queue #{missing_queue} " \
    'due to error: The specified queue does not exist'
  ),
  "the failed send must be logged without arguments: #{log.string}"
)
refute(log.string.include?('SECRET-TOKEN-123'), "log_arguments = false must keep arguments out: #{log.string}")
refute(log.string.include?('user@example.com'), "log_arguments = false must keep arguments out: #{log.string}")

assert(
  plain_line&.include?(
    "Failed to enqueue job: PlainArgumentsJob (Job ID: #{plain_job.job_id}) to queue #{missing_queue} " \
    'with arguments: "other@example.com", "PLAIN-TOKEN-456" due to error: The specified queue does not exist'
  ),
  "the failed send must be logged with arguments: #{log.string}"
)
refute(log.string.include?('message_body'), "the SQS message body must not be logged: #{log.string}")
