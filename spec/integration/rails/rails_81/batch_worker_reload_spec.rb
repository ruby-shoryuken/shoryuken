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

require_relative 'reloading_app'

setup_sqs

with_queue_and_dir do |queue, dir|
  write_reloading_app(dir, 'Rails.application.reloader.to_prepare { ReloadedBatchWorker }')

  File.write(File.join(dir, 'app', 'workers', 'reloaded_batch_worker.rb'), <<~RUBY)
    class ReloadedBatchWorker
      include Shoryuken::Worker

      shoryuken_options queue: ENV.fetch('RELOADING_QUEUE'), auto_delete: true, batch: true

      def perform(_sqs_msgs, bodies)
        puts "greeting: \#{Greeting.text}, bodies: \#{bodies.join(',')}"
      end
    end
  RUBY

  status, output = run_reloading_app(queue, dir, stop_on: 'InvalidWorkerRegistrationError')

  assert(status.success?, "shoryuken must exit cleanly, got #{status.inspect}: #{output}")
  refute(output.include?('InvalidWorkerRegistrationError'), "got: #{output}")
  assert_includes(output, 'greeting: v1, bodies: first')
  assert_includes(output, 'greeting: v2, bodies: second')
  assert_equal(0, queue_size(queue), "both messages must be processed and deleted: #{output}")
end
