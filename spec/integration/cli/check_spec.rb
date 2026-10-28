# frozen_string_literal: true

# `shoryuken check` loads the configuration and workers and validates the options, queues
# and workers like `start` does, but exits instead of processing: 0 with a short
# OK message when the setup is valid, 1 with the problem (and no backtrace) when
# it is not.

setup_sqs

def run_check(*args)
  output, status = Open3.capture2e(SHORYUKEN_ENV, RbConfig.ruby, SHORYUKEN_BIN, 'check', *args)
  [output, status.exitstatus]
end

def check_scenarios(with_worker, without_worker, dir)
  missing = DT.uuid

  worker_file = File.join(dir, 'check_worker.rb')
  File.write(worker_file, <<~RUBY)
    class CheckWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{with_worker}'
      def perform(_sqs_msg, _body); end
    end
  RUBY

  output, code = run_check('-q', with_worker, '-r', worker_file)
  assert_equal(0, code, "valid setup must exit 0, got: #{output}")
  assert_includes(output, 'Configuration OK')

  output, code = run_check(
    '-q', with_worker, '-r', worker_file, '-d', '-L', File.join(dir, 'check.log'), '-P', File.join(dir, 'check.pid')
  )
  assert_equal(0, code, "start's daemon options must be accepted, got: #{output}")
  assert_includes(output, 'Configuration OK')

  output, code = run_check('-q', with_worker, '-r', worker_file, '-d')
  assert_equal(1, code, "daemonizing without a logfile must exit 1, got: #{output}")
  assert_includes(output, "[FAIL] You should set a logfile if you're going to daemonize")

  output, code = run_check('-q', with_worker, without_worker, '-r', worker_file)
  assert_equal(1, code, "queue without a worker must exit 1, got: #{output}")
  assert_includes(output, "[FAIL] No worker supplied for #{without_worker}")
  refute(output.include?('WARN'), "problems must be reported once, not also logged as warnings, got: #{output}")

  output, code = run_check('-q', missing, '-r', worker_file)
  assert_equal(1, code, "missing queue must exit 1, got: #{output}")
  assert_includes(output, "The specified queue(s) #{missing} do not exist")
  refute(output.include?('.rb:'), "expected config errors must not print a backtrace, got: #{output}")

  output, code = run_check('-q', with_worker, '-r', worker_file, '-c', '0')
  assert_equal(1, code, "an invalid option value must exit 1, got: #{output}")
  assert_includes(output, '[FAIL]')
  assert_includes(output, 'concurrency')
  refute(output.include?('.rb:'), "an invalid option value must not print a backtrace, got: #{output}")

  output, code = run_check('-r', worker_file)
  assert_equal(1, code, "no queues must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] No queues supplied')

  output, code = run_check('-q', with_worker, '-r', File.join(dir, 'missing_worker.rb'))
  assert_equal(1, code, "missing require path must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] cannot load such file')
  refute(output.include?('.rb:'), "a missing require path must not print a backtrace, got: #{output}")

  output, code = run_check('-C', File.join(dir, 'missing.yml'))
  assert_equal(1, code, "missing config file must exit 1, got: #{output}")
  assert_includes(output, 'does not exist')

  malformed_config = File.join(dir, 'malformed.yml')
  File.write(malformed_config, "queues:\n  - [#{with_worker}\n")
  output, code = run_check('-C', malformed_config, '-r', worker_file)
  assert_equal(1, code, "malformed config file must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] (<unknown>): did not find expected')
  refute(output.include?('.rb:'), "a malformed config file must not print a backtrace, got: #{output}")

  aliased_config = File.join(dir, 'aliased.yml')
  File.write(aliased_config, "defaults: &defaults\n  - #{with_worker}\nqueues: *defaults\n")
  output, code = run_check('-C', aliased_config, '-r', worker_file)
  assert_equal(1, code, "a config file YAML refuses to load must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] Alias parsing was not enabled')
  refute(output.include?('.rb:'), "a config file YAML refuses to load must not print a backtrace, got: #{output}")
end

with_queue_and_dir do |with_worker, dir|
  with_queue_and_dir do |without_worker, _|
    check_scenarios(with_worker, without_worker, dir)
  end
end
