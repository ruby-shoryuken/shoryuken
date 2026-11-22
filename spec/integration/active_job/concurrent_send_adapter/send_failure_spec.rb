# frozen_string_literal: true

# This spec tests how ShoryukenConcurrentSendAdapter reports the outcome of its
# asynchronous sends.
#
# With no handlers, a send to a missing queue is logged by the default error
# handler as `Failed to enqueue job: ... due to error: ...`, and
# #wait_for_pending_sends returns true: a failed send counts as finished.
#
# A success handler and an error handler passed to `new` get the SQS response
# or the error, the job and the send options. The default error handler then
# logs nothing.
#
# A Shoryuken process stopped while a send is still running past its timeout
# logs `Timed out draining in-flight ActiveJob sends` and exits cleanly; the
# job never reaches SQS.

require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

setup_sqs
setup_active_job

log = StringIO.new
Shoryuken.logger = Logger.new(log)

class SendOutcomeJob < ActiveJob::Base
  def perform; end
end

# --- Default error handler ---
with_queue_and_dir do |queue, _dir|
  missing_queue = "missing-#{DT.uuid}"
  adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new
  ActiveJob::Base.queue_adapter = adapter

  SendOutcomeJob.queue_as(queue)
  SendOutcomeJob.set(queue: missing_queue).perform_later

  assert(adapter.wait_for_pending_sends(15), 'a failed send must count as finished')
  assert(
    log.string.match?(
      /Failed to enqueue job: #<SendOutcomeJob:.*"#{missing_queue}".* due to error: The specified queue does not/
    ),
    "the default error handler must log the failed send: #{log.string}"
  )
end

# --- Custom success and error handlers ---
with_queue_and_dir do |queue, _dir|
  log.truncate(0)
  log.rewind

  successes = Queue.new
  failures = Queue.new
  adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new(
    ->(response, job, options) { successes << [response, job, options] },
    ->(error, job, options) { failures << [error, job, options] }
  )
  ActiveJob::Base.queue_adapter = adapter

  SendOutcomeJob.queue_as(queue)
  sent_job = SendOutcomeJob.set(wait: 30).perform_later
  lost_job = SendOutcomeJob.set(queue: "missing-#{DT.uuid}").perform_later

  assert(adapter.wait_for_pending_sends(15), 'both sends must finish')
  assert_equal(1, successes.size, 'the success handler must run once')
  assert_equal(1, failures.size, 'the error handler must run once')

  response, job, options = successes.pop
  assert(response.message_id.is_a?(String) && !response.message_id.empty?, "got response #{response.inspect}")
  assert_equal(sent_job.job_id, job.job_id)
  assert_equal({ delay_seconds: 30 }, options)
  assert_equal(1, queue_size(queue, delayed: true), 'the successful send must reach SQS')

  error, job, options = failures.pop
  assert(error.is_a?(Aws::SQS::Errors::ServiceError), "got error #{error.inspect}")
  assert_includes(error.message, 'The specified queue does not exist')
  assert_equal(lost_job.job_id, job.job_id)
  assert_equal({}, options)

  refute(log.string.include?('Failed to enqueue job'), "a custom error handler replaces the default: #{log.string}")
end

# --- Drain timeout at shutdown ---
with_queue_and_dir do |source, dir|
  with_queue_and_dir do |target, _|
    enqueued_marker = File.join(dir, 'enqueued')
    boot_file = File.join(dir, 'boot.rb')

    File.write(boot_file, <<~RUBY)
      require 'active_job'
      require 'active_job/extensions'
      require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

      # Keeps the send in flight well past the 1 second shutdown timeout
      Shoryuken.client_middleware do |chain|
        chain.add(Class.new do
          def call(_options)
            sleep 30
            yield
          end
        end)
      end

      ActiveJob::Base.queue_adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new

      class UndrainedJob < ActiveJob::Base
        queue_as '#{target}'

        def perform; end
      end

      class EnqueueingWorker
        include Shoryuken::Worker

        shoryuken_options queue: '#{source}', auto_delete: true

        def perform(_sqs_msg, _body)
          UndrainedJob.perform_later
          File.write('#{enqueued_marker}', '')
        end
      end
    RUBY

    Shoryuken::Client.queues(source).send_message(message_body: 'trigger')

    status, output = run_shoryuken_until(
      '-q', source, '-r', boot_file, '-t', '1',
      env: { 'RUBYOPT' => '-rbundler/setup' }
    ) { File.exist?(enqueued_marker) }

    assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
    assert_includes(output, 'Draining in-flight ActiveJob sends')
    assert_includes(output, 'Timed out draining in-flight ActiveJob sends; some may not have been delivered')
    assert_equal(0, queue_size(target), "the undrained send must not reach SQS: #{output}")
  end
end
