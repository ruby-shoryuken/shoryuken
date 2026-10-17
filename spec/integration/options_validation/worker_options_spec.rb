# frozen_string_literal: true

# This spec tests that `shoryuken start` refuses to boot a worker whose
# `shoryuken_options` has an unknown key, and boots one that uses every known
# worker option.
#
# Expected behavior: a mistyped key (`auto_delte`) raises
# InvalidConfigurationError naming the worker and the key when the worker
# class loads, so the process exits with a non-zero status and processes
# nothing. A worker with only known options starts and processes the message.
#
# Regression: any key was merged into the worker options without a check, so a
# typo was silently ignored (e.g. messages were never deleted).

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

def queue_size(queue_name)
  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

  Shoryuken::Client.sqs.get_queue_attributes(
    queue_url: queue_url,
    attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
  ).attributes.values.sum(&:to_i)
end

def write_worker(dir, name, options, marker)
  boot_file = File.join(dir, "#{name}.rb")
  File.write(boot_file, <<~RUBY)
    class #{name}
      include Shoryuken::Worker

      shoryuken_options #{options}

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY
  boot_file
end

dir = Dir.mktmpdir
queue = DT.uuid
create_test_queue(queue)

marker = File.join(dir, 'processed')
config_file = File.join(dir, 'shoryuken.yml')
File.write(config_file, "queues:\n  - #{queue}\n")

Shoryuken::Client.queues(queue).send_message(message_body: 'hello')

begin
  # --- unknown key ---
  boot_file = write_worker(dir, 'TypoWorker', "queue: '#{queue}', auto_delte: true", marker)

  Open3.popen2e(ENV_VARS, RbConfig.ruby, BIN, 'start', '-C', config_file, '-r', boot_file) do |_in, out, wait|
    output = +''
    reader = Thread.new { out.each_line { |line| output << line } }

    unless wait.join(30)
      Process.kill('KILL', wait.pid)
      reader.join
      raise "the process must fail to start, but it kept running: #{output}"
    end

    reader.join

    refute(wait.value.success?, "the process must fail to start, got: #{output}")
    assert_includes(output, 'Shoryuken::Errors::InvalidConfigurationError', "got: #{output}")
    assert_includes(output, 'TypoWorker.auto_delte', "got: #{output}")
    assert_includes(output, 'is not a known worker option', "got: #{output}")
    refute(output.include?('Starting'), "the process must not start, got: #{output}")
  end

  refute(File.exist?(marker), 'no message must be processed')
  assert_equal(1, queue_size(queue), 'the message must still be in the queue')

  # --- every known option ---
  boot_file = write_worker(
    dir, 'KnownOptionsWorker',
    "queue: '#{queue}', delete: false, auto_delete: true, auto_visibility_timeout: true, " \
    'retry_intervals: [1], batch: false, body_parser: :text, non_retryable_exceptions: [ArgumentError]',
    marker
  )

  output = +''
  status = nil
  Open3.popen2e(ENV_VARS, RbConfig.ruby, BIN, 'start', '-C', config_file, '-r', boot_file) do |_in, out, wait|
    reader = Thread.new { out.each_line { |line| output << line } }

    begin
      Timeout.timeout(30) { sleep 0.1 until File.exist?(marker) || !wait.alive? }
    rescue Timeout::Error
      Process.kill('KILL', wait.pid)
    end

    unless File.exist?(marker)
      reader.join
      raise "the message must be processed, got: #{output}"
    end

    Process.kill('TERM', wait.pid)
    status = Timeout.timeout(30) { wait.value }
    reader.join
  end

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
  refute(output.include?('InvalidConfigurationError'), "got: #{output}")
ensure
  delete_test_queue(queue)
  FileUtils.remove_entry(dir)
end
