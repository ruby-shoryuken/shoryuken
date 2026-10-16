# frozen_string_literal: true

# `shoryuken check` loads the configuration and workers and validates the queues
# and workers like `start` does, but exits instead of processing: 0 with a short
# OK message when the setup is valid, 1 with the problem (and no backtrace) when
# it is not.

require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'

setup_sqs

BIN = File.expand_path('../../../bin/shoryuken', __dir__)

ENV_VARS = {
  'AWS_ENDPOINT_URL_SQS' => 'http://localhost:9324',
  'AWS_REGION' => 'us-east-1',
  'AWS_ACCESS_KEY_ID' => 'fake',
  'AWS_SECRET_ACCESS_KEY' => 'fake'
}.freeze

def run_check(*args)
  output, status = Open3.capture2e(ENV_VARS, RbConfig.ruby, BIN, 'check', *args)
  [output, status.exitstatus]
end

with_worker = DT.uuid
without_worker = DT.uuid
missing = DT.uuid

create_test_queue(with_worker)
create_test_queue(without_worker)

dir = Dir.mktmpdir

begin
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

  output, code = run_check('-q', with_worker, without_worker, '-r', worker_file)
  assert_equal(1, code, "queue without a worker must exit 1, got: #{output}")
  assert_includes(output, "[FAIL] No worker supplied for #{without_worker}")
  refute(output.include?('WARN'), "problems must be reported once, not also logged as warnings, got: #{output}")

  output, code = run_check('-q', missing, '-r', worker_file)
  assert_equal(1, code, "missing queue must exit 1, got: #{output}")
  assert_includes(output, "The specified queue(s) #{missing} do not exist")
  refute(output.include?('.rb:'), "expected config errors must not print a backtrace, got: #{output}")

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
ensure
  delete_test_queue(with_worker)
  delete_test_queue(without_worker)
  FileUtils.remove_entry(dir)
end
