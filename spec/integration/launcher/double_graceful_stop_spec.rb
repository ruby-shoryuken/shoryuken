# frozen_string_literal: true

# This spec tests that a second graceful stop returns instead of deadlocking.
#
# Operationally this is the TSTP -> USR1 sequence: Runner handles TSTP by
# calling Launcher#stop ("stop accepting new work") and a later USR1 calls
# Launcher#stop again for the final soft shutdown.
#
# Regression: Manager#await_dispatching_in_progress popped a Queue that
# received exactly one signal when the dispatch loop observed the stop flag.
# A second Launcher#stop popped an empty queue and blocked forever, leaving
# the process stuck in the signal loop where even TERM/INT were no longer
# processed - only SIGKILL could stop it.

require 'timeout'

setup_sqs

DT.clear

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

stop_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, body)
    DT[:processed] << body
  end
end

stop_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, stop_worker)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

launcher = Shoryuken::Launcher.new
launcher.start

begin
  # Prove the launcher is fully up and dispatching before stopping it
  Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'before stop')
  Timeout.timeout(10) { sleep 0.5 until DT[:processed].size >= 1 }

  # First graceful stop (TSTP: "stop accepting new work")
  Timeout.timeout(10) { launcher.stop }

  # Second graceful stop (USR1 after TSTP: final soft shutdown).
  # This must return promptly instead of blocking forever.
  begin
    Timeout.timeout(10) { launcher.stop }
  rescue Timeout::Error
    raise IntegrationsHelper::TestFailure,
          'Second Launcher#stop deadlocked: await_dispatching_in_progress blocked on an empty signal queue ' \
          '(TSTP -> USR1 leaves the process unkillable except SIGKILL)'
  end

  assert_equal(['before stop'], DT[:processed].to_a, 'Message sent before shutdown should have been processed')
ensure
  # Best-effort cleanup so a failure above never leaves a live launcher behind.
  # On the happy path this is also a third stop, exercising idempotent shutdown.
  begin
    Timeout.timeout(10) { launcher.stop }
  rescue Timeout::Error
    nil
  end
end
