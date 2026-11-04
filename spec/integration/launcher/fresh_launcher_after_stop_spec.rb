# frozen_string_literal: true

# This spec tests that stopping a launcher with the default executor leaves a
# fresh launcher in the same process able to process messages.
#
# The launcher owns its executor and shuts down and kills only that one, so a
# new launcher builds a new executor.
#
# Regression: with no launcher_executor configured, the launcher used to fall
# back to the process-wide Concurrent.global_io_executor and shut it down on
# stop, so a fresh launcher could not start in the same process.

require 'timeout'

setup_sqs

# Exercise the real default executor path. The integrations helper injects a
# dedicated pool via launcher_executor; production CLI/embedded use leaves it nil.
Shoryuken.define_singleton_method(:launcher_executor) { nil }

DT.clear

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

first_launcher = Shoryuken::Launcher.new
first_launcher.start

Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'first')
Timeout.timeout(15) { sleep 0.2 until DT[:processed].size >= 1 }

first_launcher.stop!

second_launcher = Shoryuken::Launcher.new
second_launcher.start

Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'second')
Timeout.timeout(15) { sleep 0.2 until DT[:processed].size >= 2 }

second_launcher.stop

assert_equal(%w[first second], DT[:processed].to_a, 'a fresh launcher must process messages after a stop')
