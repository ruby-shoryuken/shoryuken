# frozen_string_literal: true

# This spec tests that a Shoryuken process drains the in-flight sends of
# ShoryukenConcurrentSendAdapter before it exits.
#
# A worker enqueues a job with the concurrent adapter, which schedules the SQS
# send on a background future and returns at once. The process is then stopped
# while that send is still running: with TERM (Launcher#stop!) and with USR1
# (Launcher#stop). Both handlers call exit right after the launcher stops. The
# adapter is set on ActiveJob::Base, and in one run on the job class only. A
# last run sets no timeout (a config key with no value, e.g. an unset ERB env
# variable), which means no shutdown deadline.
#
# The launcher waits for the pending send, so the job enqueued by the worker
# reaches SQS, the drain is logged and the process exits cleanly. Without a
# timeout the drain waits with no deadline.
#
# Regression: the launcher never drained the adapter, so exit killed the send
# thread and the job was silently lost.

setup_sqs

def run_scenario(signal, adapter_on: 'ActiveJob::Base', timeout: 15)
  with_queue_and_dir do |source, dir|
    with_queue_and_dir do |target, _|
      drain_scenario(signal, source, target, dir, adapter_on: adapter_on, timeout: timeout)
    end
  end
end

def drain_scenario(signal, source, target, dir, adapter_on:, timeout:)
  name = "#{signal}_#{adapter_on.gsub('::', '_')}_timeout_#{timeout.inspect}"
  enqueued_marker = File.join(dir, "#{name}.enqueued")
  boot_file = File.join(dir, "#{name}_boot.rb")
  config_file = File.join(dir, "#{name}.yml")

  File.write(config_file, "timeout: <%= ENV['SHORYUKEN_UNSET_TIMEOUT'] %>\n") if timeout.nil?
  timeout_args = timeout.nil? ? ['-C', config_file] : ['-t', timeout.to_s]

  File.write(boot_file, <<~RUBY)
    require 'active_job'
    require 'active_job/extensions'
    require 'active_job/queue_adapters/shoryuken_concurrent_send_adapter'

    # Keeps the send in flight long enough for the stop signal to arrive first
    Shoryuken.client_middleware do |chain|
      chain.add(Class.new do
        def call(_options)
          sleep 3
          yield
        end
      end)
    end

    ActiveJob::Base.queue_adapter = :shoryuken

    class DrainedOnShutdownJob < ActiveJob::Base
      queue_as '#{target}'

      def perform; end
    end

    #{adapter_on}.queue_adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new

    class EnqueueingWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{source}', auto_delete: true

      def perform(_sqs_msg, _body)
        DrainedOnShutdownJob.perform_later
        File.write('#{enqueued_marker}', '')
      end
    end
  RUBY

  Shoryuken::Client.queues(source).send_message(message_body: 'trigger')

  target_size_at_signal = nil
  status, output = run_shoryuken_until('-q', source, '-r', boot_file, *timeout_args, signal: signal) do
    next false unless File.exist?(enqueued_marker)

    target_size_at_signal = queue_size(target)
    true
  end

  assert_equal(0, target_size_at_signal, "#{name}: the send must still be in flight when #{signal} is sent")
  assert(status.success?, "#{name}: the process must exit cleanly, got #{status.inspect}: #{output}")

  assert_equal(1, queue_size(target), "#{name}: the job enqueued before shutdown must reach SQS, got: #{output}")
  assert_includes(output, 'Draining in-flight ActiveJob sends', "#{name}: the drain must be logged, got: #{output}")
end

run_scenario('TERM')
run_scenario('USR1')
run_scenario('TERM', adapter_on: 'DrainedOnShutdownJob')
run_scenario('TERM', timeout: nil)
