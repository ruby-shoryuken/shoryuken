# frozen_string_literal: true

# This spec tests that `shoryuken start` accepts valid configurations, including
# values that are coerced where they are used, and processes messages with them.
#
# Expected behavior: with the defaults, with numeric Strings and fractional
# weights (config file `delay: '5'`, `[queue, 1.5]`, CLI `-q queue,2.5`), with
# an unset timeout and with a processing group, the process starts, processes
# the message, logs no validation error or warning and exits cleanly on TERM.

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

def expect_processed(dir, name, queue, config, *args)
  marker = File.join(dir, "#{name}.processed")
  boot_file = File.join(dir, "#{name}_boot.rb")
  File.write(boot_file, <<~RUBY)
    class ValidValuesWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY

  config_args = []
  if config
    config_file = File.join(dir, "#{name}.yml")
    File.write(config_file, config)
    config_args = ['-C', config_file]
  end

  Shoryuken::Client.queues(queue).send_message(message_body: name)

  output = +''
  status = nil
  Open3.popen2e(ENV_VARS, RbConfig.ruby, BIN, 'start', '-r', boot_file, *config_args, *args) do |_in, out, wait|
    reader = Thread.new { out.each_line { |line| output << line } }

    begin
      Timeout.timeout(30) { sleep 0.1 until File.exist?(marker) || !wait.alive? }
    rescue Timeout::Error
      Process.kill('KILL', wait.pid)
    end

    unless File.exist?(marker)
      reader.join
      raise "#{name}: the message must be processed, got: #{output}"
    end

    Process.kill('TERM', wait.pid)
    status = Timeout.timeout(30) { wait.value }
    reader.join
  end

  assert(status.success?, "#{name}: the process must exit cleanly, got #{status.inspect}: #{output}")
  refute(output.include?('InvalidConfigurationError'), "#{name}: no validation error expected, got: #{output}")
  refute(output.include?('Unknown option'), "#{name}: no unknown option warning expected, got: #{output}")
  assert_equal(0, queue_size(queue), "#{name}: the message must be deleted")
end

dir = Dir.mktmpdir
queue = DT.uuid
create_test_queue(queue)

begin
  # --- defaults, queue from the CLI ---
  expect_processed(dir, 'defaults', queue, nil, '-q', queue)

  # --- coerced values and an unset timeout in the config file ---
  expect_processed(dir, 'config_file', queue, <<~YAML)
    delay: '5'
    timeout: <%= ENV['SHORYUKEN_UNSET_TIMEOUT'] %>
    queues:
      - [#{queue}, 1.5]
  YAML

  # --- CLI values, including a fractional queue weight ---
  expect_processed(dir, 'cli', queue, nil, '-q', "#{queue},2.5", '-c', '2', '-t', '10', '-D', '0.5')

  # --- processing group ---
  expect_processed(dir, 'group', queue, <<~YAML)
    concurrency: 2
    groups:
      custom:
        concurrency: 1
        delay: '0'
        polling_strategy: StrictPriority
        queues:
          - [#{queue}, 2]
  YAML
ensure
  delete_test_queue(queue)
  FileUtils.remove_entry(dir)
end
