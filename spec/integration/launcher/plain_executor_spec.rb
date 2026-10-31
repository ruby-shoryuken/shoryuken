# frozen_string_literal: true

# This spec tests that a launcher_executor does not have to be a concurrent-ruby
# executor: any object with post, running?, shutdown, wait_for_termination and
# kill works.
#
# It used to fail: Manager#assign ran each message in a Concurrent::Promise on
# the executor, and Concurrent::Promise accepts only a Concurrent::ExecutorService,
# so every assign raised "executor not recognized" and no message was processed.
#
# Expected behavior: the launcher processes and deletes the messages on the
# plain executor and shuts it down on stop.

require 'timeout'

# Runs each posted block on a new thread
class PlainExecutor
  def initialize
    @threads = []
    @mutex = Mutex.new
    @running = true
  end

  def post(&block)
    @mutex.synchronize do
      raise Concurrent::RejectedExecutionError unless @running

      @threads << Thread.new(&block)
    end

    true
  end

  def running?
    @running
  end

  def shutdown
    @mutex.synchronize { @running = false }
  end

  def wait_for_termination(timeout = nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout if timeout

    @threads.all? do |thread|
      remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max if deadline
      thread.join(remaining)
    end
  end

  def kill
    shutdown
    @threads.each(&:kill)
  end
end

setup_sqs

DT.clear

executor = PlainExecutor.new
Shoryuken.define_singleton_method(:launcher_executor) { executor }

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 2)
Shoryuken.add_queue(queue_name, 1, 'default')

worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

launcher = Shoryuken::Launcher.new
launcher.start

bodies = %w[first second third]
bodies.each { |body| Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: body) }

Timeout.timeout(15) { sleep 0.2 until DT[:processed].size >= bodies.size }

launcher.stop

assert_equal(bodies.sort, DT[:processed].sort)
refute(executor.running?, 'Launcher#stop should shut the plain executor down')
assert_equal(0, queue_size(queue_name))
