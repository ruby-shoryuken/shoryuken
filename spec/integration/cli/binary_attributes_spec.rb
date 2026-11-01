# frozen_string_literal: true

# This spec tests `shoryuken sqs dump` and `shoryuken sqs requeue` with Binary
# message attributes, and a dump that stops while it writes its file.
#
# `dump` stores Binary attribute values as base64 and marks them with
# `binary_value_encoding`, so a value that is not valid UTF-8 survives dump
# and requeue byte for byte. A dump file without the mark (raw values) still
# requeues. A dump that stops before it finishes leaves no file and deletes
# no message, so the next dump of the queue that day can run.
#
# Regression: dump raised JSON::GeneratorError on a Binary value that is not
# valid UTF-8 and left an empty dump file, so every later dump of the queue
# that day failed with "File ... already exists".

setup_sqs

def queue_url(queue)
  Shoryuken::Client.sqs.get_queue_url(queue_name: queue).queue_url
end

def receive_one(queue)
  Shoryuken::Client.sqs.receive_message(
    queue_url: queue_url(queue), message_attribute_names: ['All'], wait_time_seconds: 1
  ).messages.first
end

binary = "\xFF\x00\xFE".b

# --- dump and requeue ---
with_queue_and_dir do |queue, dir|
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url(queue), message_body: 'binary',
    message_attributes: {
      'b' => { data_type: 'Binary', binary_value: binary },
      's' => { data_type: 'String', string_value: 'text' }
    }
  )

  status, output = run_shoryuken_sqs('dump', queue, '-p', dir)
  assert(status.success?, "dump must succeed, got: #{output}")

  path = Dir[File.join(dir, '*.jsonl')].first
  attribute = JSON.parse(File.read(path))['message_attributes']['b']
  assert_equal('base64', attribute['binary_value_encoding'], "got: #{attribute}")
  assert_equal([binary].pack('m0'), attribute['binary_value'], "got: #{attribute}")

  status, output = run_shoryuken_sqs('requeue', queue, path)
  assert(status.success?, "requeue must succeed, got: #{output}")

  message = receive_one(queue)
  assert_equal(binary, message.message_attributes['b'].binary_value.b, 'the Binary value must survive dump and requeue')
  assert_equal('text', message.message_attributes['s'].string_value)
end

# --- requeue of a dump file with raw Binary values ---
with_queue_and_dir do |queue, dir|
  path = File.join(dir, 'old.jsonl')
  line = {
    message_id: DT.uuid, body: 'old', attributes: {},
    message_attributes: { b: { data_type: 'Binary', binary_value: 'raw value' } }
  }
  File.write(path, JSON.dump(line))

  status, output = run_shoryuken_sqs('requeue', queue, path)
  assert(status.success?, "requeue must succeed, got: #{output}")
  assert_equal('raw value', receive_one(queue).message_attributes['b'].binary_value)
end

# --- a dump that stops while it writes ---
with_queue_and_dir do |queue, dir|
  Shoryuken::Client.sqs.send_message(queue_url: queue_url(queue), message_body: 'kept')

  status, output = run_shoryuken_sqs_until('dump', queue, '-p', dir, signal: 'INT') do
    Dir[File.join(dir, '*.jsonl')].any?
  end

  refute(status.success?, "an interrupted dump must exit with a non-zero status, got: #{output}")
  assert_equal([], Dir[File.join(dir, '*')], 'a dump that stops must leave no file')
  assert_equal(1, queue_size(queue), 'a dump that stops must delete no message')
end
