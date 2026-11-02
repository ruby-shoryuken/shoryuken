# frozen_string_literal: true

def write_reloading_app(dir, initializer)
  FileUtils.mkdir_p(File.join(dir, 'config', 'initializers'))
  FileUtils.mkdir_p(File.join(dir, 'app', 'models'))
  FileUtils.mkdir_p(File.join(dir, 'app', 'workers'))

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

    #{initializer}
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

def run_reloading_app(queue, dir, stop_on: nil)
  # Backdated so the rewrite below always has a newer mtime for the file watcher
  old_time = Time.now - 60
  File.utime(old_time, old_time, write_greeting(dir, 'v1'))

  Shoryuken::Client.queues(queue).send_message(message_body: 'first')

  env = {
    'RUBYOPT' => '-rbundler/setup',
    'RELOADING_QUEUE' => queue
  }
  edited = false

  run_shoryuken_until('-R', '-q', queue, env: env, chdir: dir) do |log, _pid|
    if !edited && log.include?('greeting: v1')
      write_greeting(dir, 'v2')
      Shoryuken::Client.queues(queue).send_message(message_body: 'second')
      edited = true
    end

    log.include?('greeting: v2') || (stop_on && log.include?(stop_on))
  end
end
