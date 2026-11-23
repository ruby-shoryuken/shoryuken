# frozen_string_literal: true

# This spec tests that a Rails app enqueueing with `perform_later` reads the aws section of config/shoryuken.yml under
# `Rails.root`, with ERB that uses `Rails.env`, while the process runs in another directory and has no AWS settings
# in the environment.
#
# Regression: only `shoryuken -C` read the aws section, so `perform_later` raised Aws::Errors::MissingRegionError.

setup_sqs

def write_rails_app(dir)
  FileUtils.mkdir_p(File.join(dir, 'config', 'environments'))

  File.write(File.join(dir, 'config', 'application.rb'), <<~RUBY)
    require 'rails'
    require 'active_job/railtie'
    require 'shoryuken'
    require 'active_job/queue_adapters/shoryuken_adapter'
    require 'active_job/extensions'

    module AwsConfigApp
      class Application < Rails::Application
        config.root = '#{dir}'
        config.logger = Logger.new(nil)
        config.active_job.queue_adapter = :shoryuken
      end
    end
  RUBY

  File.write(File.join(dir, 'config', 'environment.rb'), <<~RUBY)
    require_relative 'application'

    Rails.application.initialize!
  RUBY

  File.write(File.join(dir, 'config', 'environments', 'production.rb'), <<~RUBY)
    Rails.application.configure do
      config.eager_load = false
    end
  RUBY

  File.write(File.join(dir, 'config', 'shoryuken.yml'), <<~YAML)
    aws:
      region: us-east-1
      endpoint: <%= Rails.env.production? ? 'http://localhost:9324' : 'http://localhost:1' %>
      access_key_id: fake
      secret_access_key: fake
  YAML
end

def write_producer(dir, app_dir, queue)
  path = File.join(dir, 'producer.rb')

  File.write(path, <<~RUBY)
    require '#{File.join(app_dir, 'config', 'environment')}'

    class AwsConfigJob < ActiveJob::Base
      queue_as '#{queue}'

      def perform; end
    end

    AwsConfigJob.perform_later
    puts 'enqueued'
  RUBY

  path
end

with_queue_and_dir do |queue, dir|
  app_dir = File.join(dir, 'app')
  cwd = File.join(dir, 'elsewhere')
  FileUtils.mkdir_p(cwd)
  write_rails_app(app_dir)

  env = %w[
    AWS_ENDPOINT_URL_SQS AWS_ENDPOINT_URL AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  ].to_h { |name| [name, nil] }.merge(
    'AWS_CONFIG_FILE' => File.join(dir, 'no-aws-config'),
    'AWS_SHARED_CREDENTIALS_FILE' => File.join(dir, 'no-aws-credentials'),
    'RUBYOPT' => '-rbundler/setup',
    'RAILS_ENV' => 'production'
  )

  status, output = run_ruby_script_until_exit(write_producer(dir, app_dir, queue), env: env, chdir: cwd)

  assert_equal(0, status.exitstatus, "perform_later must enqueue, got: #{output}")
  assert_includes(output, 'enqueued')
  assert_equal(1, queue_size(queue), 'The job must reach ElasticMQ')
end
