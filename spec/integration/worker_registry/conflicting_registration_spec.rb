# frozen_string_literal: true

# This spec tests `shoryuken start` with workers registered for the same queue
# more than once.
#
# A batch worker and a second worker on one queue, in either order, stop the
# process before it starts with an InvalidWorkerRegistrationError naming both
# workers, and the waiting message is not processed. A non-batch worker whose
# file is loaded twice (an eager load run twice) registers again without an
# error, and the process starts and processes the message with it. A batch
# worker whose file is loaded twice does the same.
#
# Regression: #623

def write_workers(dir, queue, marker, batch_first:)
  batch_worker = <<~RUBY
    class ConflictingBatchWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true, batch: true

      def perform(_sqs_msgs, _bodies)
        File.write('#{marker}', '')
      end
    end
  RUBY

  single_worker = <<~RUBY
    class ConflictingSingleWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY

  boot_file = File.join(dir, "conflicting_#{batch_first}.rb")
  File.write(boot_file, batch_first ? batch_worker + single_worker : single_worker + batch_worker)
  boot_file
end

def write_reloaded_worker(dir, queue, marker, batch:)
  worker_file = File.join(dir, "reloaded_worker_#{batch}.rb")
  File.write(worker_file, <<~RUBY)
    class ReloadedWorker#{batch ? 'Batch' : 'Single'}
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true, batch: #{batch}

      def perform(_sqs_msg, body)
        File.write('#{marker}', Array(body).join)
      end
    end
  RUBY

  boot_file = File.join(dir, "reload_#{batch}.rb")
  File.write(boot_file, "load '#{worker_file}'\nload '#{worker_file}'\n")
  boot_file
end

setup_sqs

with_queue_and_dir do |queue, dir|
  marker = File.join(dir, 'processed')
  Shoryuken::Client.queues(queue).send_message(message_body: 'must not be processed')

  [
    %w[ConflictingSingleWorker ConflictingBatchWorker],
    %w[ConflictingBatchWorker ConflictingSingleWorker]
  ].each do |registered, rejected|
    boot_file = write_workers(dir, queue, marker, batch_first: registered == 'ConflictingBatchWorker')

    status, output = run_shoryuken_until_exit('-q', queue, '-r', boot_file)

    refute(status.success?, "the process must fail to start, got: #{output}")
    assert_includes(output, 'Shoryuken::Errors::InvalidWorkerRegistrationError', "got: #{output}")
    assert_includes(
      output,
      "Could not register #{rejected} for #{queue}, because #{registered} is already registered for this queue",
      "got: #{output}"
    )
    refute(output.include?('Starting'), "the process must not start, got: #{output}")
  end

  refute(File.exist?(marker), 'no worker may process the message')
  assert_equal(1, queue_size(queue), 'the message must not be deleted')
end

[false, true].each do |batch|
  with_queue_and_dir do |queue, dir|
    marker = File.join(dir, 'processed')
    boot_file = write_reloaded_worker(dir, queue, marker, batch: batch)

    Shoryuken::Client.queues(queue).send_message(message_body: 'reloaded')

    status, output = run_shoryuken_until('-q', queue, '-r', boot_file) { File.exist?(marker) }

    assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
    refute(output.include?('InvalidWorkerRegistrationError'), "got: #{output}")
    assert_equal('reloaded', File.read(marker))
    assert_equal(0, queue_size(queue), 'the message must be processed and deleted')
  end
end
