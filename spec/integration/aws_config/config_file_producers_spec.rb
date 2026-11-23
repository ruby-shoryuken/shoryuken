# frozen_string_literal: true

# This spec tests that the aws section of config/shoryuken.yml reaches the processes that do not run the worker,
# with no AWS settings in the environment: a plain Ruby script that enqueues a raw worker and an ActiveJob job, and
# `shoryuken sqs`, both with the file in the current directory and with `sqs -C <path>`.
#
# Regression: only `shoryuken -C` read the aws section, so the script and `shoryuken sqs` raised
# Aws::Errors::MissingRegionError.

setup_sqs

NO_AWS_ENV = %w[
  AWS_ENDPOINT_URL_SQS AWS_ENDPOINT_URL AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY SHORYUKEN_SQS_ENDPOINT
].to_h { |name| [name, nil] }.freeze

def write_config(path)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(
    path,
    <<~YAML
      aws:
        region: us-east-1
        endpoint: http://localhost:9324
        access_key_id: fake
        secret_access_key: fake
    YAML
  )
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

  missing = File.join(dir, 'missing.yml')
  status, output = run_shoryuken_command_until_exit('sqs', 'ls', '-C', missing, env: sqs_env(dir), chdir: dir)

  assert_equal(1, status.exitstatus, "sqs ls -C with a missing file must fail, got: #{output}")
  assert_includes(output, "[FAIL] The supplied config file #{missing} does not exist")
end
