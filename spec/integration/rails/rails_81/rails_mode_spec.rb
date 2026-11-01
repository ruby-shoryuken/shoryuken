# frozen_string_literal: true

# This spec tests `shoryuken start -R -C config/shoryuken.yml` in a Rails app
# running in production, with a worker in `app/workers` and no `-r`.
#
# It used to read the config file before Rails booted, so ERB in it that uses
# values set by the app (`Rails.configuration`, dotenv) raised
# `uninitialized constant Rails` or found nothing.
#
# Rails boots and runs its initializers first, then the
# config file is parsed with access to them. The app eager loads
# `app/workers`, so the worker is registered for the queue the config names,
# processes a message and deletes it.
#
# Regression: #422

setup_sqs

def write_rails_app(dir)
  FileUtils.mkdir_p(File.join(dir, 'config', 'environments'))
  FileUtils.mkdir_p(File.join(dir, 'config', 'initializers'))
  FileUtils.mkdir_p(File.join(dir, 'app', 'workers'))

  File.write(File.join(dir, 'config', 'application.rb'), <<~RUBY)
    require 'rails'

    module RailsModeApp
      class Application < Rails::Application
        config.root = '#{dir}'
        config.logger = Logger.new(nil)
      end
    end
  RUBY

  File.write(File.join(dir, 'config', 'environment.rb'), <<~RUBY)
    require_relative 'application'

    Rails.application.initialize!
  RUBY

  File.write(File.join(dir, 'config', 'environments', 'production.rb'), <<~RUBY)
    Rails.application.configure do
      config.eager_load = true
    end
  RUBY

  File.write(File.join(dir, 'config', 'initializers', 'queue.rb'), <<~RUBY)
    Rails.configuration.x.rails_mode_queue = ENV.fetch('RAILS_MODE_QUEUE')
  RUBY

  File.write(File.join(dir, 'config', 'shoryuken.yml'), <<~YAML)
    queues:
      - <%= Rails.configuration.x.rails_mode_queue %>
  YAML

  File.write(File.join(dir, 'app', 'workers', 'rails_mode_worker.rb'), <<~RUBY)
    $stdout.sync = true

    class RailsModeWorker
      include Shoryuken::Worker

      shoryuken_options queue: Rails.configuration.x.rails_mode_queue, auto_delete: true

      def perform(_sqs_msg, body)
        puts "worker ran: \#{body}"
      end
    end
  RUBY
end

with_queue_and_dir do |queue, dir|
  write_rails_app(dir)
  Shoryuken::Client.queues(queue).send_message(message_body: 'from rails mode')

  env = {
    'RUBYOPT' => '-rbundler/setup',
    'RAILS_ENV' => 'production',
    'RAILS_MODE_QUEUE' => queue
  }

  status, output = run_shoryuken_until('-R', '-C', 'config/shoryuken.yml', env: env, chdir: dir) do |log, _pid|
    log.include?('worker ran')
  end

  assert(status.success?, "shoryuken must exit cleanly, got #{status.inspect}: #{output}")
  assert_includes(output, 'worker ran: from rails mode')
  refute(output.include?('No worker'), "the app/workers worker must be registered: #{output}")
  assert_equal(0, queue_size(queue), "the message must be processed and deleted: #{output}")
end
