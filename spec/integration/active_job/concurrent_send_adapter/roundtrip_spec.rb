# frozen_string_literal: true

# This spec tests ShoryukenConcurrentSendAdapter in a Rails app started with
# `shoryuken start -R`, where the app sets
# `config.active_job.queue_adapter = :shoryuken_concurrent_send`.
#
# It used to fail at boot with `NameError: uninitialized constant
# ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter`: the CLI requires
# shoryuken before Rails loads ActiveJob, so the adapter was never required.
#
# The process boots with the adapter resolved by its symbol. A job it runs
# enqueues a follow-up job, which is sent on another thread than the
# enqueuing one and then runs. A send to a missing queue reaches the
# adapter's error handler, which logs it.
#
# Regression: #641

setup_sqs
setup_active_job

def write_rails_app(dir)
  FileUtils.mkdir_p(File.join(dir, 'config', 'initializers'))

  File.write(File.join(dir, 'config', 'application.rb'), <<~RUBY)
    require 'rails'
    require 'active_job/railtie'

    module ConcurrentSendApp
      class Application < Rails::Application
        config.root = '#{dir}'
        config.eager_load = false
        config.logger = Logger.new(nil)
        config.active_job.queue_adapter = :shoryuken_concurrent_send
      end
    end
  RUBY

  File.write(File.join(dir, 'config', 'environment.rb'), <<~RUBY)
    require_relative 'application'

    Rails.application.initialize!
  RUBY

  File.write(File.join(dir, 'config', 'initializers', 'jobs.rb'), <<~RUBY)
    $stdout.sync = true

    Shoryuken.client_middleware do |chain|
      chain.add(Class.new do
        def call(_options)
          puts "send thread: \#{Thread.current.object_id}"
          yield
        end
      end)
    end

    class FollowUpJob < ActiveJob::Base
      queue_as ENV.fetch('ROUNDTRIP_QUEUE')

      def perform(adapter)
        puts "follow-up ran, enqueued with \#{adapter}"
      end
    end

    class LostJob < ActiveJob::Base
      queue_as ENV.fetch('ROUNDTRIP_MISSING_QUEUE')

      def perform; end
    end

    class TriggerJob < ActiveJob::Base
      def perform
        puts "enqueue thread: \#{Thread.current.object_id}"
        FollowUpJob.perform_later(ActiveJob::Base.queue_adapter.class.name)
        LostJob.perform_later
      end
    end
  RUBY
end

def thread_ids(output, label)
  output.scan(/^#{label} thread: (\d+)$/).flatten
end

class TriggerJob < ActiveJob::Base
  def perform; end
end

with_queue_and_dir do |queue, dir|
  write_rails_app(dir)
  missing_queue = "missing-#{DT.uuid}"

  TriggerJob.queue_as(queue)
  TriggerJob.perform_later

  env = {
    'RUBYOPT' => '-rbundler/setup',
    'ROUNDTRIP_QUEUE' => queue,
    'ROUNDTRIP_MISSING_QUEUE' => missing_queue
  }

  status, output = run_shoryuken_until('-R', '-q', queue, env: env, chdir: dir) do |log, _pid|
    log.include?('follow-up ran') && log.include?('Failed to enqueue job')
  end

  assert(status.success?, "shoryuken must exit cleanly, got #{status.inspect}: #{output}")
  assert_includes(output, 'follow-up ran, enqueued with ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter')

  enqueue_threads = thread_ids(output, 'enqueue')
  send_threads = thread_ids(output, 'send')
  assert_equal(1, send_threads.size, "only the follow-up must reach the SQS send: #{output}")
  refute(enqueue_threads.include?(send_threads.first), "the follow-up must be sent asynchronously: #{output}")

  assert(
    output.match?(/Failed to enqueue job: #<LostJob:.*"#{missing_queue}".* due to error: The specified queue does not/),
    "the send error must reach the error handler: #{output}"
  )
  assert_equal(0, queue_size(queue), "both jobs must be processed and deleted: #{output}")
end
