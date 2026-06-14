# frozen_string_literal: true

# This spec tests that a fatal dispatch error does not hard-kill the host
# process when Shoryuken runs embedded (Launcher used directly, without the
# CLI Runner).
#
# When the dispatch loop hits an unrecoverable error (e.g. SQS still failing
# after the fetcher exhausts its retries), Manager#handle_dispatch_error used
# to send Process.kill('USR1', Process.pid) unconditionally. The CLI Runner
# traps USR1 and turns it into a graceful shutdown, but an embedded host has
# USR1's default disposition, which terminates the whole process - killing any
# in-flight workers.
#
# Expected behavior when embedded: the failing manager stops itself and
# Launcher#healthy? reports the failure; no process-killing signal is sent.
#
# Regression: embedded mode received an untrapped USR1 and the process died.

require 'timeout'

setup_sqs

DT.clear

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

embedded_worker = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true

  def perform(_sqs_msg, _body); end
end

embedded_worker.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, embedded_worker)

# Force every fetch to fail so the dispatch loop reaches handle_dispatch_error.
# Prepend (rather than redefine) to avoid method-redefinition warnings.
failing_fetch = Module.new do
  def fetch(*)
    raise 'simulated persistent fetch failure'
  end
end
Shoryuken::Fetcher.prepend(failing_fetch)

# Safely observe whether the process is signalled with USR1. A real embedded
# host has the default (lethal) disposition; here we trap it only so the test
# runner survives long enough to assert that the signal is not sent. The trap
# runs on the main thread, so a plain boolean assignment (no lock, no
# allocation) is trap-safe and visible to the assertions below.
usr1_received = false
previous_handler = Signal.trap('USR1') { usr1_received = true }

launcher = Shoryuken::Launcher.new
launcher.start

begin
  # The failing dispatch should drive the manager - and therefore the launcher -
  # unhealthy.
  Timeout.timeout(15) { sleep 0.2 while launcher.healthy? }

  # Give any (buggy) USR1 a chance to be delivered and handled.
  sleep 1

  refute(
    usr1_received,
    'Embedded mode must not send USR1 on a fatal dispatch error: with no Runner ' \
    'trapping it, the default disposition terminates the host process and its ' \
    'in-flight workers'
  )

  assert(!launcher.healthy?, 'Launcher should report unhealthy after a fatal dispatch error')
ensure
  Signal.trap('USR1', previous_handler || 'DEFAULT')

  begin
    Timeout.timeout(10) { launcher.stop }
  rescue Timeout::Error
    nil
  end
end
