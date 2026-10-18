# frozen_string_literal: true

# This spec tests that lifecycle event handlers registered on the global
# options do not leak into the defaults of new Shoryuken::Options instances.
#
# Expected behavior: a launcher processing a message fires each handler once,
# and a new Shoryuken::Options instance, like Options::DEFAULTS, has no
# handlers.
#
# Regression: Options#options copied DEFAULTS shallowly, so `on` appended
# handlers to the nested arrays of DEFAULTS, and every later instance fired
# them too.

setup_sqs

DT.clear

Shoryuken.on(:startup) { DT[:events] << :startup }
Shoryuken.on(:shutdown) { DT[:events] << :shutdown }

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

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'lifecycle events')

poll_queues_until { DT[:processed].any? }

assert_equal(['lifecycle events'], DT[:processed])
assert_equal(%i[startup shutdown], DT[:events], 'Each registered handler must fire once')

fresh_events = Shoryuken::Options.new.options[:lifecycle_events]
assert(fresh_events.values.all?(&:empty?), "A new Options instance must have no handlers: #{fresh_events.inspect}")
assert(Shoryuken::Options::DEFAULTS[:lifecycle_events].values.all?(&:empty?), 'DEFAULTS must stay empty')

delete_test_queue(queue_name)
