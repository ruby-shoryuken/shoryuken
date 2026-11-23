# frozen_string_literal: true

# This spec tests that the aws section of config/shoryuken.yml reaches the processes that do not run the worker,
# with no AWS settings in the environment: a plain Ruby script that enqueues a raw worker and an ActiveJob job, and
# `shoryuken sqs`, both with the file in the current directory and with `sqs -C <path>`. `-e` wins over the file's
# endpoint.
#
# A config/shoryuken.yml in the current directory that `shoryuken sqs` cannot read (ERB that needs Rails or does
# not compile, invalid YAML) does not stop the command: it warns and uses `-e`. A `-C` file that cannot be read prints
# one `[FAIL]` line and exits with status 1.
#
# Regression: only `shoryuken -C` read the aws section, so the script and `shoryuken sqs` raised
# Aws::Errors::MissingRegionError.

setup_sqs

NO_AWS_ENV = %w[
  AWS_ENDPOINT_URL_SQS AWS_ENDPOINT_URL AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY SHORYUKEN_SQS_ENDPOINT
].to_h { |name| [name, nil] }.freeze

def write_config(path, endpoint: 'http://localhost:9324')
  write_file(
    path,
    <<~YAML
      aws:
        region: us-east-1
        endpoint: #{endpoint}
        access_key_id: fake
        secret_access_key: fake
    YAML
  )
end

def write_file(path, content)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
end

def assert_sqs_fails(dir, path, message)
  status, output = run_shoryuken_command_until_exit('sqs', 'ls', '-C', path, env: sqs_env(dir), chdir: dir)

  assert_equal(1, status.exitstatus, "sqs ls -C #{path} must fail, got: #{output}")
  assert_includes(output, message)
  refute(output.include?('.rb:'), "sqs ls -C #{path} must not print a backtrace, got: #{output}")
end

def write_producer(dir, queue)
  path = File.join(dir, 'producer.rb')
  File.write(
    path,
    <<~RUBY
      require 'shoryuken'
      require 'active_job'
      require 'active_job/queue_adapters/shoryuken_adapter'
      require 'active_job/extensions'

      class ProducerWorker
        include Shoryuken::Worker

        shoryuken_options queue: '#{queue}'

        def perform(sqs_msg, body); end
      end

      class ProducerJob < ActiveJob::Base
        queue_as '#{queue}'

        def perform; end
      end

      ActiveJob::Base.queue_adapter = :shoryuken

      ProducerWorker.perform_async('raw')
      ProducerJob.perform_later
      puts 'enqueued'
    RUBY
  )
  path
end

def sqs_env(dir)
  NO_AWS_ENV.merge(
    'AWS_CONFIG_FILE' => File.join(dir, 'no-aws-config'),
    'AWS_SHARED_CREDENTIALS_FILE' => File.join(dir, 'no-aws-credentials')
  )
end

with_queue_and_dir do |queue, dir|
  write_config(File.join(dir, 'config', 'shoryuken.yml'))

  status, output = run_shoryuken_command_until_exit(
    'enqueue', bin: write_producer(dir, queue), env: sqs_env(dir), chdir: dir
  )

  assert_equal(0, status.exitstatus, "The producer must enqueue, got: #{output}")
  assert_includes(output, 'enqueued')
  assert_equal(2, queue_size(queue), 'Both messages must reach ElasticMQ')

  status, output = run_shoryuken_command_until_exit('sqs', 'ls', queue, env: sqs_env(dir), chdir: dir)

  assert_equal(0, status.exitstatus, "sqs ls must use config/shoryuken.yml, got: #{output}")
  assert_includes(output, queue)
end

with_queue_and_dir do |queue, dir|
  config = File.join(dir, 'custom', 'worker.yml')
  write_config(config)

  status, output = run_shoryuken_command_until_exit('sqs', 'ls', queue, '-C', config, env: sqs_env(dir), chdir: dir)

  assert_equal(0, status.exitstatus, "sqs ls -C must use the given file, got: #{output}")
  assert_includes(output, queue)

  unreachable = File.join(dir, 'custom', 'unreachable.yml')
  write_config(unreachable, endpoint: 'http://localhost:1')

  status, output = run_shoryuken_command_until_exit(
    'sqs', 'ls', queue, '-C', unreachable, '-e', 'http://localhost:9324', env: sqs_env(dir), chdir: dir
  )

  assert_equal(0, status.exitstatus, "-e must win over the file's endpoint, got: #{output}")
  assert_includes(output, queue)

  missing = File.join(dir, 'missing.yml')
  assert_sqs_fails(dir, missing, "[FAIL] The supplied config file #{missing} does not exist")

  not_mapping = File.join(dir, 'not_mapping.yml')
  write_file(not_mapping, "aws: us-east-1\n")
  assert_sqs_fails(dir, not_mapping, "[FAIL] The aws section of #{not_mapping} must be a mapping")

  assert_sqs_fails(dir, File.join(dir, 'custom'), "[FAIL] Could not read the config file #{File.join(dir, 'custom')}")

  raising = File.join(dir, 'raising.yml')
  write_file(raising, "aws:\n  region: <%= raise 'no region' %>\n")
  assert_sqs_fails(dir, raising, "[FAIL] Could not read the config file #{raising}: RuntimeError: no region")

  erb_typo = File.join(dir, 'erb_typo.yml')
  write_file(erb_typo, "aws:\n  region: <%= 1 + %>\n")
  assert_sqs_fails(dir, erb_typo, "[FAIL] Could not read the config file #{erb_typo}: SyntaxError")
end

with_queue_and_dir do |queue, dir|
  config = File.join(dir, 'config', 'shoryuken.yml')

  ["aws:\n  region: <%= Rails.env %>\n", "aws:\n  region: <%= 1 + %>\n", "aws: [\n"].each do |content|
    write_file(config, content)

    status, output = run_shoryuken_command_until_exit(
      'sqs', 'ls', queue, '-e', 'http://localhost:9324',
      env: sqs_env(dir).merge('AWS_REGION' => 'us-east-1', 'AWS_ACCESS_KEY_ID' => 'fake', 'AWS_SECRET_ACCESS_KEY' => 'fake'),
      chdir: dir
    )

    assert_equal(0, status.exitstatus, "An unreadable #{config} must not stop sqs ls, got: #{output}")
    assert_includes(output, queue)
    assert_includes(output, "Could not read the aws section of #{config}, ignoring it")
    refute(output.include?('.rb:'), "sqs ls must not print a backtrace, got: #{output}")
  end
end
