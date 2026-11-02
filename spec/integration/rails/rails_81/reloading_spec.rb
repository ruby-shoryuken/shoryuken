# frozen_string_literal: true

# This spec tests `Shoryuken.enable_reloading` in a Rails 8.1 app started with
# `shoryuken start -R`, where the app has `config.enable_reloading = true`.
#
# Each message a plain Shoryuken worker processes runs inside the Rails
# reloader, so inside the app's executor too. When an autoloaded file
# changes between two messages, the second one sees the new code without a
# restart.

require_relative 'reloading_app'

setup_sqs

with_queue_and_dir do |queue, dir|
  write_reloading_app(dir, <<~RUBY)
    class GreetingWorker
      include Shoryuken::Worker

      shoryuken_options queue: ENV.fetch('RELOADING_QUEUE'), auto_delete: true

      def perform(_sqs_msg, _body)
        puts "greeting: \#{Greeting.text}, executor active: \#{Rails.application.executor.active?}"
      end
    end
  RUBY

  status, output = run_reloading_app(queue, dir)

  assert(status.success?, "shoryuken must exit cleanly, got #{status.inspect}: #{output}")
  assert_includes(output, 'greeting: v1, executor active: true')
  assert_includes(output, 'greeting: v2, executor active: true')
  assert_equal(0, queue_size(queue), "both messages must be processed and deleted: #{output}")
end
