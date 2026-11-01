# frozen_string_literal: true

# This spec tests `Shoryuken.enable_reloading` in a Rails 8.1 app started with
# `shoryuken start -R`, where the app has `config.enable_reloading = true`.
#
# Each message a plain Shoryuken worker processes runs
# inside the Rails reloader, so inside the app's executor too. When an
# autoloaded file changes between two messages, the second one sees the new
# code without a restart.

setup_sqs

def write_rails_app(dir)
  FileUtils.mkdir_p(File.join(dir, 'config', 'initializers'))
  FileUtils.mkdir_p(File.join(dir, 'app', 'models'))

  File.write(File.join(dir, 'config', 'application.rb'), <<~RUBY)
    require 'rails'

    module ReloadingApp
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

    class GreetingWorker
      include Shoryuken::Worker

      shoryuken_options queue: ENV.fetch('RELOADING_QUEUE'), auto_delete: true

      def perform(_sqs_msg, _body)
        puts "greeting: \#{Greeting.text}, executor active: \#{Rails.application.executor.active?}"
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
    'RELOADING_QUEUE' => queue
  }
  edited = false

  status, output = run_shoryuken_until('-R', '-q', queue, env: env, chdir: dir) do |log, _pid|
    if !edited && log.include?('greeting: v1')
      write_greeting(dir, 'v2')
      Shoryuken::Client.queues(queue).send_message(message_body: 'second')
      edited = true
    end

    log.include?('greeting: v2')
  end

  assert(status.success?, "shoryuken must exit cleanly, got #{status.inspect}: #{output}")
  assert_includes(output, 'greeting: v1, executor active: true')
  assert_includes(output, 'greeting: v2, executor active: true')
  assert_equal(0, queue_size(queue), "both messages must be processed and deleted: #{output}")
end
