# frozen_string_literal: true

# This spec tests that `shoryuken start` validates the global options once they
# are loaded from the config file and the CLI.
#
# Expected behavior:
# - An invalid value (`concurrency: 0` in the config file, a negative `-t` on
#   the CLI, a group whose `queues` is not a list) stops the process before it
#   starts, with an InvalidConfigurationError naming the option.
# - An unknown key (a mistyped `concurency`, globally or in a group) logs a
#   warning naming the key, and the process starts and processes messages.
#
# Regression: any key was merged into the options without a check, so a typo
# was silently ignored and an invalid value failed later, or not at all.

require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'
require 'timeout'

setup_sqs

BIN = File.expand_path('../../../bin/shoryuken', __dir__)

ENV_VARS = {
  'AWS_ENDPOINT_URL_SQS' => 'http://localhost:9324',
  'AWS_REGION' => 'us-east-1',
  'AWS_ACCESS_KEY_ID' => 'fake',
  'AWS_SECRET_ACCESS_KEY' => 'fake'
}.freeze

def start_shoryuken(dir, config, *args)
  config_file = File.join(dir, "#{DT.uuid}.yml")
  File.write(config_file, config)

  Open3.popen2e(ENV_VARS, RbConfig.ruby, BIN, 'start', '-C', config_file, *args) do |_in, out, wait|
    yield out, wait
  end
end

def expect_rejected(dir, config, message, *args)
  start_shoryuken(dir, config, *args) do |out, wait|
    output = +''
    reader = Thread.new { out.each_line { |line| output << line } }

    unless wait.join(30)
      Process.kill('KILL', wait.pid)
      reader.join
      raise "the process must fail to start, but it kept running: #{output}"
    end

    reader.join
    status = wait.value

    refute(status.success?, "the process must fail to start, got: #{output}")
    assert_includes(output, 'Shoryuken::Errors::InvalidConfigurationError', "got: #{output}")
    assert_includes(output, message, "got: #{output}")
    refute(output.include?('Starting'), "the process must not start, got: #{output}")
  end
end

dir = Dir.mktmpdir
queue = DT.uuid
create_test_queue(queue)

begin
  # --- invalid value in the config file ---
  expect_rejected(dir, "concurrency: 0\nqueues:\n  - #{queue}\n", 'Invalid value for concurrency: 0')

  # --- invalid value on the CLI ---
  expect_rejected(dir, "queues:\n  - #{queue}\n", 'Invalid value for timeout: -1', '-t', '-1')

  # --- invalid group option ---
  expect_rejected(dir, "groups:\n  custom:\n    queues: #{queue}\n", "Invalid value for groups.custom.queues: \"#{queue}\"")

  # --- unknown keys: warned, the process still runs ---
  marker = File.join(dir, 'processed')
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class OptionsValidationWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY

  Shoryuken::Client.queues(queue).send_message(message_body: 'hello')

  config = <<~YAML
    concurency: 2
    groups:
      custom:
        dealy: 5
        queues:
          - #{queue}
  YAML

  output = +''
  start_shoryuken(dir, config, '-r', boot_file) do |out, wait|
    reader = Thread.new { out.each_line { |line| output << line } }

    Timeout.timeout(30) { sleep 0.1 until File.exist?(marker) }

    Process.kill('TERM', wait.pid)
    Timeout.timeout(30) { wait.value }
    reader.join
  end

  assert_includes(output, "Unknown option 'concurency' is ignored", "got: #{output}")
  assert_includes(output, "Unknown option 'groups.custom.dealy' is ignored", "got: #{output}")
ensure
  delete_test_queue(queue)
  FileUtils.remove_entry(dir)
end
