# frozen_string_literal: true

# This spec tests that `shoryuken start` refuses to run with an invalid option
# value, from the config file or from the CLI, globally or in a group.
#
# Expected behavior: the process exits with a non-zero status before it starts.
# The InvalidConfigurationError names every invalid option by its key path
# (`groups.<name>.<key>` inside a group) with its message, and the message
# waiting in the queue is not processed.
#
# Regression: any value was merged into the options without a check, so the
# process started and failed later (e.g. a Manager crash on a nil
# concurrency), or ran with a value it could not use.

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

def queue_size(queue_name)
  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

  Shoryuken::Client.sqs.get_queue_attributes(
    queue_url: queue_url,
    attribute_names: %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
  ).attributes.values.sum(&:to_i)
end

# Starts shoryuken with the given config file content and CLI arguments, and
# checks that it fails to start, reporting each [key path, message] pair
def expect_rejected(dir, boot_file, config, errors, *args)
  config_file = File.join(dir, "#{DT.uuid}.yml")
  File.write(config_file, config)

  Open3.popen2e(ENV_VARS, RbConfig.ruby, BIN, 'start', '-C', config_file, '-r', boot_file, *args) do |_in, out, wait|
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
    errors.each do |key, message|
      assert_includes(output, key, "got: #{output}")
      assert_includes(output, message, "got: #{output}")
    end
    refute(output.include?('Starting'), "the process must not start, got: #{output}")
  end
end

dir = Dir.mktmpdir
queue = DT.uuid
create_test_queue(queue)

marker = File.join(dir, 'processed')
boot_file = File.join(dir, 'boot.rb')
File.write(boot_file, <<~RUBY)
  class InvalidValuesWorker
    include Shoryuken::Worker

    shoryuken_options queue: '#{queue}', auto_delete: true

    def perform(_sqs_msg, _body)
      File.write('#{marker}', '')
    end
  end
RUBY

Shoryuken::Client.queues(queue).send_message(message_body: 'must not be processed')

queues = "queues:\n  - #{queue}\n"
concurrency = ['concurrency', 'needs to be an Integer greater than 0']
delay = ['delay', 'needs to be nil or a number greater than or equal to 0']

begin
  # --- config file ---
  expect_rejected(dir, boot_file, "concurrency: 0\n#{queues}", [concurrency])
  expect_rejected(dir, boot_file, "delay: soon\n#{queues}", [delay])
  expect_rejected(dir, boot_file, "queues:\n  - [#{queue}, high]\n",
                  [['queues', 'needs to be nil or an Array of queue names or [name, weight] pairs']])

  # --- CLI ---
  expect_rejected(dir, boot_file, queues, [concurrency], '-c', '-1')
  expect_rejected(dir, boot_file, queues, [['timeout', 'needs to be nil or a number greater than or equal to 0']],
                  '-t', '-1')

  # --- groups ---
  expect_rejected(dir, boot_file, "groups:\n  custom:\n    concurrency: 0\n    queues:\n      - #{queue}\n",
                  [['groups.custom.concurrency', 'needs to be nil or an Integer greater than 0']])
  expect_rejected(dir, boot_file, "groups:\n  custom:\n    queues: #{queue}\n",
                  [['groups.custom.queues', 'needs to be nil or an Array of queue names']])
  expect_rejected(dir, boot_file, "groups:\n  custom:\n    - #{queue}\n", [['groups.custom', 'needs to be a Hash']])

  # --- every invalid option is reported at once ---
  expect_rejected(dir, boot_file, "concurrency: 0\ndelay: -1\n#{queues}", [concurrency, delay])

  refute(File.exist?(marker), 'no message must be processed')
  assert_equal(1, queue_size(queue), 'the message must still be in the queue')
ensure
  delete_test_queue(queue)
  FileUtils.remove_entry(dir)
end
