# frozen_string_literal: true

# This spec tests how `shoryuken sqs dump`, `mv` and `delete` handle their input and report the result.
#
# `dump` with a missing or read-only `-p` directory and `dump`/`mv` with `-n 0` fail with a
# `[FAIL]` message before they receive any message, so the messages stay available. `delete` reports the deleted
# queue.
#
# Regression: `dump -p <missing or read-only dir>` received the messages and then raised `Errno::ENOENT` or
# `Errno::EACCES`, which left them in flight; `-n 0` raised `Aws::SQS::Errors::InvalidAttributeValue`; `delete`
# printed "was successfully delete".

setup_sqs

def send_messages(queue)
  url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  2.times { |i| Shoryuken::Client.sqs.send_message(queue_url: url, message_body: "message-#{i}") }
end

def available_messages(queue)
  url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
  Shoryuken::Client.sqs.get_queue_attributes(
    queue_url: url, attribute_names: %w[ApproximateNumberOfMessages]
  ).attributes['ApproximateNumberOfMessages'].to_i
end

# --- dump to a missing directory ---
with_queue_and_dir do |queue, dir|
  send_messages(queue)
  missing = File.join(dir, 'missing')

  status, output = run_shoryuken_sqs('dump', queue, '-p', missing)

  refute(status.success?, "dump must exit with a non-zero status, got: #{output}")
  assert_includes(output, "[FAIL] Path #{missing} is not a directory", "got: #{output}")
  refute(output.include?('Errno::ENOENT'), "dump must not raise, got: #{output}")
  assert_equal(2, available_messages(queue), 'the messages must stay available, not in flight')
end

# --- dump to a directory it cannot write to (no w, or no x to create a file) ---
if Process.uid.zero?
  puts 'Skipping the read-only directory scenario: root can write to any directory'
else
  [0o555, 0o600].each do |mode|
    with_queue_and_dir do |queue, dir|
      send_messages(queue)
      File.chmod(mode, dir)

      begin
        status, output = run_shoryuken_sqs('dump', queue, '-p', dir)
      ensure
        File.chmod(0o700, dir)
      end

      refute(status.success?, "dump must exit with a non-zero status, got: #{output}")
      assert_includes(output, "[FAIL] Path #{dir} is not writable", "mode #{mode.to_s(8)}, got: #{output}")
      assert_equal(2, available_messages(queue), "mode #{mode.to_s(8)}: the messages must stay available")
    end
  end
end

# --- dump and mv with -n 0 ---
with_queue_and_dir do |queue, dir|
  with_queue_and_dir do |target, _target_dir|
    send_messages(queue)

    [['dump', queue, '-p', dir, '-n', '0'], ['mv', queue, target, '-n', '0']].each do |args|
      status, output = run_shoryuken_sqs(*args)

      refute(status.success?, "#{args.first} must exit with a non-zero status, got: #{output}")
      assert_includes(output, '[FAIL] Number of messages must be at least 1, got 0', "got: #{output}")
      refute(output.include?('InvalidAttributeValue'), "#{args.first} must not reach SQS, got: #{output}")
    end

    assert_equal(2, available_messages(queue), 'the messages must stay available, not in flight')
    assert_equal(0, queue_size(target), 'mv must move nothing')
    assert_equal([], Dir.children(dir), 'dump must write no file')
  end
end

# --- delete ---
queue = DT.uuid
create_test_queue(queue)

status, output = run_shoryuken_sqs('delete', queue)

assert(status.success?, "delete must succeed, got: #{output}")
assert_includes(output, "Queue #{queue} was successfully deleted", "got: #{output}")
