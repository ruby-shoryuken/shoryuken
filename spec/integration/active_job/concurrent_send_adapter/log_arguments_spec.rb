# frozen_string_literal: true

# This spec tests that the default error handler of
# ShoryukenConcurrentSendAdapter honours ActiveJob `log_arguments`.
#
# It used to log `job.inspect` on a failed send, so the job arguments and the
# SQS message body reached the log even for a job with
# `self.log_arguments = false`.
#
# The send itself fails here, after the message body is built: a FIFO queue
# without content-based deduplication rejects a message with no deduplication
# id. A job with `log_arguments = false` is logged with its class, job id,
# queue and the error, but none of its arguments. A job that keeps the default
# `log_arguments = true` also gets its arguments, formatted as the Rails
# enqueue line does: a GlobalID record as its global id, not its attributes.
# A record without an id cannot be serialized, so its send fails before SQS;
# it is still logged, as the record itself.

require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

setup_sqs
setup_active_job

GlobalID.app = 'shoryuken'
Shoryuken.active_job_fifo_message_deduplication = false
Shoryuken.fifo_message_deduplication = false

log = StringIO.new
Shoryuken.logger = Logger.new(log)

class User
  include GlobalID::Identification

  attr_reader :id, :email

  def self.find(id)
    new(id, 'record@example.com')
  end

  def initialize(id, email)
    @id = id
    @email = email
  end
end

class SecretArgumentsJob < ActiveJob::Base
  self.log_arguments = false

  def perform(_email, _token); end
end

class PlainArgumentsJob < ActiveJob::Base
  def perform(_user, _options); end
end

with_queue_and_dir(fifo: true, attributes: { 'ContentBasedDeduplication' => 'false' }) do |queue, _dir|
  adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new
  ActiveJob::Base.queue_adapter = adapter

  secret_job = SecretArgumentsJob.set(queue: queue).perform_later('user@example.com', 'SECRET-TOKEN-123')
  plain_job = PlainArgumentsJob.set(queue: queue).perform_later(
    User.new(1, 'record@example.com'),
    { users: [User.new(2, 'nested@example.com')], note: 'PLAIN-NOTE' }
  )
  unsaved_job = PlainArgumentsJob.set(queue: queue).perform_later(User.new(nil, 'unsaved@example.com'), {})

  assert(adapter.wait_for_pending_sends(15), 'the failed sends must count as finished')
  assert_equal(0, queue_size(queue), "both sends must fail: #{log.string}")

  secret_line = log.string.lines.find { |line| line.include?("Job ID: #{secret_job.job_id}") }
  plain_line = log.string.lines.find { |line| line.include?("Job ID: #{plain_job.job_id}") }
  unsaved_line = log.string.lines.find { |line| line.include?("Job ID: #{unsaved_job.job_id}") }

  assert(
    secret_line&.include?(
      "Failed to enqueue job: SecretArgumentsJob (Job ID: #{secret_job.job_id}) to queue #{queue} due to error: "
    ),
    "the failed send must be logged without arguments: #{log.string}"
  )
  refute(log.string.include?('SECRET-TOKEN-123'), "log_arguments = false must keep arguments out: #{log.string}")
  refute(log.string.include?('user@example.com'), "log_arguments = false must keep arguments out: #{log.string}")

  assert(
    plain_line&.include?(
      "Failed to enqueue job: PlainArgumentsJob (Job ID: #{plain_job.job_id}) to queue #{queue} with arguments: "
    ),
    "the failed send must be logged with arguments: #{log.string}"
  )
  assert(plain_line.include?('gid://shoryuken/User/1'), "a record must be logged as its global id: #{log.string}")
  assert(plain_line.include?('gid://shoryuken/User/2'), "a nested record must be logged as its global id: #{log.string}")
  assert(
    plain_line.include?({ note: 'PLAIN-NOTE' }.inspect[1..-2]),
    "a plain argument must be logged: #{log.string}"
  )
  refute(log.string.include?('record@example.com'), "a record's attributes must not be logged: #{log.string}")
  refute(log.string.include?('nested@example.com'), "a record's attributes must not be logged: #{log.string}")

  assert(
    unsaved_line&.include?('due to error: Unable to serialize User without an id'),
    "a record without a global id must not stop the failed send from being logged: #{log.string}"
  )

  refute(log.string.include?('message_body'), "the SQS message body must not be logged: #{log.string}")
end
