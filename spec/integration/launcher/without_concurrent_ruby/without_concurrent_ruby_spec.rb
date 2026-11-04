# frozen_string_literal: true

# This spec tests that Shoryuken processes messages in a bundle without
# concurrent-ruby. The launcher runs the dispatch loop and the workers on its
# own thread pool, and nothing loads concurrent-ruby.
#
# It used to need concurrent-ruby: the gemspec depended on it and
# `require 'shoryuken'` loaded it.

require 'timeout'

setup_sqs

# The integrations helper injects a dedicated pool via launcher_executor; leave
# it nil so the launcher builds its default executor, as the CLI does.
Shoryuken.define_singleton_method(:launcher_executor) { nil }

DT.clear

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
assert_equal(0, queue_size(queue_name))
refute(Gem.loaded_specs.key?('concurrent-ruby'), 'concurrent-ruby must not be in the bundle')
refute(defined?(Concurrent), 'nothing may load concurrent-ruby')
