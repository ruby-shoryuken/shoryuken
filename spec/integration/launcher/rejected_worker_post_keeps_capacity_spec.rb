# frozen_string_literal: true

# This spec tests that a group keeps processing after the launcher executor
# rejects some of its worker posts.
#
# Manager#assign counts a processor as busy before it posts the worker. When the
# post is rejected, it rolls the busy counter back. With concurrency 1, a leaked
# count leaves no ready processor, so the group stops fetching and processing.
#
# Regression: a rejected worker post stayed counted as busy, so with a bounded
# executor dispatch stalled and the group silently stopped processing (#1029).

require 'timeout'

setup_sqs

DT.clear

REJECTED_POSTS = 3
MESSAGES = REJECTED_POSTS + 2

# Accepts the dispatch loop's posts and rejects only the first REJECTED_POSTS
# worker posts (those come from Manager#assign), then accepts them all.
rejecting_executor_class = Class.new(Concurrent::CachedThreadPool) do
  def post(*args, &block)
    if DT[:rejected].size < REJECTED_POSTS &&
       caller_locations.any? { |l| l.base_label == 'assign' && l.path.end_with?('shoryuken/manager.rb') }
      DT[:rejected] << true
      raise Concurrent::RejectedExecutionError
    end

    super
  end
end

executor = rejecting_executor_class.new(auto_terminate: true)
Shoryuken.define_singleton_method(:launcher_executor) { executor }

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
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

Shoryuken.on(:utilization_update) do |opts|
  DT[:utilization] << opts.dup
end

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
MESSAGES.times do |i|
  Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: "message-#{i}")
end

launcher = Shoryuken::Launcher.new
launcher.start

begin
  Timeout.timeout(30) { sleep 0.05 until DT[:processed].uniq.size >= MESSAGES }
ensure
  Timeout.timeout(20) { launcher.stop }
end

assert_equal(REJECTED_POSTS, DT[:rejected].size)
assert_equal(
  Array.new(MESSAGES) { |i| "message-#{i}" },
  DT[:processed].uniq.sort,
  'the group must keep processing after rejected worker posts'
)
assert_equal(0, DT[:utilization].last[:busy_processors])
assert_equal(0, queue_size(queue_name))
