# frozen_string_literal: true

# This spec tests how `shoryuken sqs purge`, `delete`, `dump`, `requeue` and `mv` handle a queue that does not exist.
#
# Each command prints `[FAIL] The specified queue <name> does not exist` and exits with status 1, also when
# ElasticMQ reports the missing queue as `QueueDoesNotExist`.
#
# Regression: on ElasticMQ the commands printed a backtrace ending in `(Aws::SQS::Errors::QueueDoesNotExist)`.

setup_sqs

def assert_missing_queue(missing, *args)
  status, output = run_shoryuken_sqs(*args)

  assert_equal(1, status.exitstatus, "#{args.first} must exit with status 1, got: #{output}")
  assert_includes(output, "[FAIL] The specified queue #{missing} does not exist", "#{args.first}, got: #{output}")
  refute(output.include?('Aws::SQS::Errors'), "#{args.first} must not raise, got: #{output}")
end

with_queue_and_dir do |queue, dir|
  missing = "#{queue}-missing"
  path = File.join(dir, 'dump.jsonl')
  File.write(path, "#{JSON.generate(body: 'message')}\n")

  assert_missing_queue(missing, 'purge', missing)
  assert_missing_queue(missing, 'delete', missing)
  assert_missing_queue(missing, 'dump', missing, '-p', dir)
  assert_missing_queue(missing, 'requeue', missing, path)
  assert_missing_queue(missing, 'mv', missing, queue)
  assert_missing_queue(missing, 'mv', queue, missing)
end
