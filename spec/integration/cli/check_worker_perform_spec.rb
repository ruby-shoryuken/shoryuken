# frozen_string_literal: true

# This spec tests that `shoryuken check` fails for a worker whose `perform`
# cannot take the message and its body, and that `shoryuken start` logs the same
# problem as a warning and still boots. Every worker of the queue is checked,
# also one registered before another worker of the same queue, except an
# abstract base worker (no perform, with a subclass) that is not the last one
# registered for the queue.
#
# The processor calls `perform(sqs_msg, body)`. A Sidekiq-style
# `perform(name)` or a typo (`preform`) used to pass `check` and fail on every
# message, which came back after each visibility timeout.

setup_sqs

def write_worker(dir, name, queue, definition)
  worker_file = File.join(dir, "#{name}.rb")
  File.write(worker_file, <<~RUBY)
    class #{name}
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      #{definition}
    end
  RUBY
  worker_file
end

def write_shared_queue_workers(dir, queue)
  worker_file = File.join(dir, 'shared_queue_workers.rb')
  File.write(worker_file, <<~RUBY)
    class SharedSigWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      def perform(name); end
    end

    class SharedGoodWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      def perform(_sqs_msg, _body); end
    end
  RUBY
  worker_file
end

def write_base_workers(dir, queue)
  worker_file = File.join(dir, 'base_workers.rb')
  File.write(worker_file, <<~RUBY)
    class ApplicationWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}', auto_delete: true
    end

    class ChildWorker < ApplicationWorker
      shoryuken_options body_parser: :json
      def perform(_sqs_msg, _body); end
    end
  RUBY
  worker_file
end

def write_base_with_subclass_elsewhere(dir, queue, other_queue)
  worker_file = File.join(dir, 'base_with_subclass_elsewhere.rb')
  File.write(worker_file, <<~RUBY)
    class ElsewhereApplicationWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
    end

    class ElsewhereChildWorker < ElsewhereApplicationWorker
      shoryuken_options queue: '#{other_queue}'
      def perform(_sqs_msg, _body); end
    end

    class ElsewhereOtherWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      def perform(_sqs_msg, _body); end
    end
  RUBY
  worker_file
end

def write_typo_before_valid_worker(dir, queue)
  worker_file = File.join(dir, 'typo_before_valid_worker.rb')
  File.write(worker_file, <<~RUBY)
    class SharedTypoWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      def preform(_sqs_msg, _body); end
    end

    class SharedValidWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      def perform(_sqs_msg, _body); end
    end
  RUBY
  worker_file
end

with_queue_and_dir do |queue, dir|
  # --- perform with one argument ---
  worker_file = write_worker(dir, 'SigWorker', queue, 'def perform(name); end')

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(1, status.exitstatus, "a wrong perform signature must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] SigWorker#perform must accept (sqs_msg, body); it takes (name)')
  refute(output.include?('Configuration OK'), "got: #{output}")
  refute(output.include?('WARN'), "problems must be reported once, not also logged as warnings, got: #{output}")
  refute(output.include?('.rb:'), "a wrong perform signature must not print a backtrace, got: #{output}")

  status, output = run_shoryuken_until('-q', queue, '-r', worker_file) { |log| log.include?('Starting') }
  assert_includes(
    output, 'WARN: SigWorker#perform must accept (sqs_msg, body); it takes (name)', "got: #{output}"
  )
  assert_includes(output, 'Starting', "start must keep booting, got: #{output}")
  assert(status.success?, "start must keep booting and stop cleanly, got: #{output}")

  # --- no perform ---
  worker_file = write_worker(dir, 'TypoWorker', queue, 'def preform(_sqs_msg, _body); end')

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(1, status.exitstatus, "a missing perform must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] TypoWorker must define perform(sqs_msg, body)')
end

with_queue_and_dir do |queue, dir|
  # --- a wrong worker registered before a valid one on the same queue ---
  worker_file = write_shared_queue_workers(dir, queue)

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(1, status.exitstatus, "a wrong worker sharing its queue must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] SharedSigWorker#perform must accept (sqs_msg, body); it takes (name)')
  refute(output.include?('SharedGoodWorker'), "got: #{output}")

  # --- an abstract base worker that sets the queue, and its subclass ---
  worker_file = write_base_workers(dir, queue)

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(0, status.exitstatus, "an abstract base worker must not fail check, got: #{output}")
  assert_includes(output, 'Configuration OK')

  # --- perform with the message and body ---
  worker_file = write_worker(dir, 'GoodWorker', queue, 'def perform(_sqs_msg, _body); end')

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(0, status.exitstatus, "a valid perform must exit 0, got: #{output}")
  assert_includes(output, 'Configuration OK')
end

with_queue_and_dir do |queue, dir|
  with_queue_and_dir do |other_queue, _|
    # --- an abstract base worker whose subclass sets another queue ---
    worker_file = write_base_with_subclass_elsewhere(dir, queue, other_queue)

    status, output = run_shoryuken_command_until_exit('check', '-q', queue, other_queue, '-r', worker_file)
    assert_equal(0, status.exitstatus, "an abstract base worker must not fail check, got: #{output}")
    assert_includes(output, 'Configuration OK')
  end

  # --- a worker without perform and without a subclass before a valid one on the same queue ---
  worker_file = write_typo_before_valid_worker(dir, queue)

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(1, status.exitstatus, "a missing perform must exit 1, got: #{output}")
  assert_includes(output, '[FAIL] SharedTypoWorker must define perform(sqs_msg, body)')
end
