# frozen_string_literal: true

# This spec tests that lifecycle event handlers registered on one
# Shoryuken::Options instance do not fire for a fresh one.
#
# Expected behavior: after the global options are replaced with a new instance,
# a launcher processing a message fires only the handlers registered on the new
# instance.
#
# Regression: Options#options copied DEFAULTS shallowly, so `on` appended
# handlers to the nested arrays of DEFAULTS, and every later instance fired
# them too.

setup_sqs

DT.clear

Shoryuken.on(:startup) { DT[:stale] << :startup }
Shoryuken.on(:shutdown) { DT[:stale] << :shutdown }

Shoryuken.instance_variable_set(:@_shoryuken_options, Shoryuken::Options.new)
setup_sqs

Shoryuken.on(:startup) { DT[:fresh] << :startup }
Shoryuken.on(:shutdown) { DT[:fresh] << :shutdown }

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
Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'fresh options')

poll_queues_until { DT[:processed].any? }

assert_equal(['fresh options'], DT[:processed])
assert_equal(%i[startup shutdown], DT[:fresh], 'Handlers on the new options must fire')
assert(DT[:stale].empty?, "Handlers on the replaced options must not fire, fired: #{DT[:stale].inspect}")
assert(Shoryuken::Options::DEFAULTS[:lifecycle_events].values.all?(&:empty?), 'DEFAULTS must stay empty')

delete_test_queue(queue_name)
