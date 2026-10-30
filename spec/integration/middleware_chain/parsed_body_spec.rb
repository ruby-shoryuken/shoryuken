# frozen_string_literal: true

# This spec tests what server middleware receives as the body when the worker
# has a body_parser.
#
# Expected behavior:
# - Middleware gets the same parsed object that perform gets (equal?)
# - sqs_msg.body stays the raw String

setup_sqs

queue_name = DT.uuid
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

class BodyRecordingMiddleware
  def call(_worker, _queue, sqs_msg, body)
    DT[:middleware] << [sqs_msg.message_id, sqs_msg.body, body]
    yield
  end
end

Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: queue_name, auto_delete: true, body_parser: :json

  server_middleware do |chain|
    chain.add BodyRecordingMiddleware
  end

  def perform(sqs_msg, body)
    DT[:perform] << [sqs_msg.message_id, sqs_msg.body, body]
  end
end

bodies = [
  JSON.dump('name' => 'test', 'nested' => { 'key' => 'val' }),
  JSON.dump([1, 'two'])
]

Shoryuken::Client.queues(queue_name).send_messages(
  entries: bodies.map { |body| { id: SecureRandom.uuid, message_body: body } }
)

poll_queues_until { DT[:perform].size >= bodies.size }

assert_equal(bodies.size, DT[:middleware].size)
assert_equal(bodies.size, DT[:perform].size)

DT[:perform].each do |message_id, raw, body|
  _, middleware_raw, middleware_body = DT[:middleware].find { |id, _, _| id == message_id }

  assert_equal(String, raw.class)
  assert_equal(raw, middleware_raw)
  assert_equal(JSON.parse(raw), body)
  assert(middleware_body.equal?(body), "Middleware got a different object than perform for #{raw}")
end
