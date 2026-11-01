# frozen_string_literal: true

# This spec tests the exit status of `shoryuken start` when a fatal dispatch error stops it: every SQS receive keeps
# failing, so the fetcher gives up after its retries and the manager stops the process.
#
# The process logs the failure, soft-shuts down and exits with status 1, so a process supervisor (systemd
# `Restart=on-failure`, Kubernetes) restarts it. A USR1 or TERM sent by an operator still exits with status 0
# (signals/on_sigusr1_spec.rb, signals/on_sigterm_spec.rb).
#
# Regression: the process exited with status 0, so `Restart=on-failure` never restarted it.

setup_sqs

with_queue_and_dir do |queue, dir|
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class FatalDispatchWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body); end
    end

    module FailingReceive
      def receive_messages(_options)
        raise Seahorse::Client::NetworkingError, StandardError.new('connection refused')
      end
    end

    Shoryuken::Queue.prepend(FailingReceive)
  RUBY

  status, output = run_shoryuken_until_exit('-q', queue, '-r', boot_file)

  assert_equal(1, status.exitstatus, "must exit with status 1, got #{status.inspect}: #{output}")
  assert_includes(output, 'Manager failed: connection refused', "got: #{output}")
  assert_includes(output, 'Received USR1, will soft shutdown', "got: #{output}")
end
