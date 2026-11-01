# frozen_string_literal: true

# This spec tests the body_parser option with batch workers (:json and a Proc).
#
# - Each message in a batch gets its own parsed body
# - bodies[i] matches sqs_msgs[i]

setup_sqs

json_queue = DT.uuid
proc_queue = DT.uuid
create_test_queue(json_queue)
create_test_queue(proc_queue)
Shoryuken.add_group('default', 2)
Shoryuken.add_queue(json_queue, 1, 'default')
Shoryuken.add_queue(proc_queue, 1, 'default')

def batch_worker(queue_name, body_parser)
  Class.new do
    include Shoryuken::Worker

    shoryuken_options queue: queue_name, auto_delete: true, batch: true, body_parser: body_parser

    def perform(sqs_msgs, bodies)
      DT[:batch_sizes] << sqs_msgs.size
      sqs_msgs.zip(bodies).each { |sqs_msg, body| DT[:received] << [sqs_msg.message_id, sqs_msg.body, body] }
    end
  end
end

batch_worker(json_queue, :json)
batch_worker(proc_queue, proc { |sqs_msg| "proc:#{sqs_msg.message_id}:#{sqs_msg.body}" })

json_bodies = 5.times.map { |i| JSON.dump('index' => i, 'items' => [i, "item-#{i}"]) }
proc_bodies = 5.times.map { |i| "plain-#{i}" }

Shoryuken::Client.queues(json_queue).send_messages(
  entries: json_bodies.map { |body| { id: SecureRandom.uuid, message_body: body } }
)
Shoryuken::Client.queues(proc_queue).send_messages(
  entries: proc_bodies.map { |body| { id: SecureRandom.uuid, message_body: body } }
)

poll_queues_until { DT[:received].size >= 10 }

assert_equal(10, DT[:received].size)
assert(DT[:batch_sizes].any? { |size| size > 1 }, 'Expected at least one batch with size > 1')

json_received = DT[:received].select { |_, raw, _| json_bodies.include?(raw) }
assert_equal(json_bodies.sort, json_received.map { |_, raw, _| raw }.sort)
json_received.each do |_, raw, body|
  assert_equal(JSON.parse(raw), body)
end

proc_received = DT[:received].select { |_, raw, _| proc_bodies.include?(raw) }
assert_equal(proc_bodies.sort, proc_received.map { |_, raw, _| raw }.sort)
proc_received.each do |message_id, raw, body|
  assert_equal("proc:#{message_id}:#{raw}", body)
end

assert_equal(0, queue_size(json_queue))
assert_equal(0, queue_size(proc_queue))
