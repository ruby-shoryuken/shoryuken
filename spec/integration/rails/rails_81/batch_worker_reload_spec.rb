# frozen_string_literal: true

# This spec tests a batch worker autoloaded by a Rails 8.1 app started with
# `shoryuken start -R`, where the app has `config.enable_reloading = true`.
#
# A `to_prepare` hook loads the worker at boot and again after each code
# reload. When an autoloaded file changes between two batches, the reload
# defines the worker class again and it registers again for its queue without
# an error, so the second batch runs the new code.
#
# Regression: #623

setup_sqs

def write_rails_app(dir)
  FileUtils.mkdir_p(File.join(dir, 'config', 'initializers'))
  FileUtils.mkdir_p(File.join(dir, 'app', 'models'))
  FileUtils.mkdir_p(File.join(dir, 'app', 'workers'))

  File.write(File.join(dir, 'config', 'application.rb'), <<~RUBY)
    require 'rails'

    module BatchReloadApp
      class Application < Rails::Application
        config.root = '#{dir}'
        config.eager_load = false
        config.enable_reloading = true
        config.logger = Logger.new(nil)
      end
    end
  RUBY

  File.write(File.join(dir, 'config', 'environment.rb'), <<~RUBY)
    require_relative 'application'

    Rails.application.initialize!
  RUBY

  File.write(File.join(dir, 'config', 'initializers', 'shoryuken.rb'), <<~RUBY)
    $stdout.sync = true

    Shoryuken.enable_reloading = true

    Rails.application.reloader.to_prepare { ReloadedBatchWorker }
  RUBY

  File.write(File.join(dir, 'app', 'workers', 'reloaded_batch_worker.rb'), <<~RUBY)
    class ReloadedBatchWorker
      include Shoryuken::Worker

      shoryuken_options queue: ENV.fetch('BATCH_RELOAD_QUEUE'), auto_delete: true, batch: true

      def perform(_sqs_msgs, bodies)
        puts "greeting: \#{Greeting.text}, bodies: \#{bodies.join(',')}"
      end
    end
  RUBY
end

def write_greeting(dir, text)
  path = File.join(dir, 'app', 'models', 'greeting.rb')

  File.write(path, <<~RUBY)
    class Greeting
      class << self
        def text
          '#{text}'
        end
      end
    end
  RUBY

  path
end

with_queue_and_dir do |queue, dir|
  write_rails_app(dir)
  # Backdated so the rewrite below always has a newer mtime for the file watcher
  old_time = Time.now - 60
  File.utime(old_time, old_time, write_greeting(dir, 'v1'))

  Shoryuken::Client.queues(queue).send_message(message_body: 'first')

  env = {
    'RUBYOPT' => '-rbundler/setup',
    'BATCH_RELOAD_QUEUE' => queue
  }
  edited = false

  status, output = run_shoryuken_until('-R', '-q', queue, env: env, chdir: dir) do |log, _pid|
    if !edited && log.include?('greeting: v1')
      write_greeting(dir, 'v2')
      Shoryuken::Client.queues(queue).send_message(message_body: 'second')
      edited = true
    end

    log.include?('greeting: v2') || log.include?('InvalidWorkerRegistrationError')
  end

  assert(status.success?, "shoryuken must exit cleanly, got #{status.inspect}: #{output}")
  refute(output.include?('InvalidWorkerRegistrationError'), "got: #{output}")
  assert_includes(output, 'greeting: v1, bodies: first')
  assert_includes(output, 'greeting: v2, bodies: second')
  assert_equal(0, queue_size(queue), "both messages must be processed and deleted: #{output}")
end
