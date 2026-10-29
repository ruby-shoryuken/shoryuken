# frozen_string_literal: true

# This spec tests that a body parser returning nil or false runs once per message
# Regression: the parsed body was memoized with ||=, so a falsy result was parsed again for the log context,
# the server middleware and perform (three parser calls per message)

setup_sqs

queue_name = DT.uuid
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

falsy_parser = proc do |sqs_msg|
  DT[:parsed_message_ids] << sqs_msg.message_id
  sqs_msg.body == 'false' ? false : nil
end

worker_class = Class.new do
  include Shoryuken::Worker

  def perform(sqs_msg, body)
    DT[:performed] << [sqs_msg.body, body]
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
worker_class.get_shoryuken_options['auto_delete'] = true
worker_class.get_shoryuken_options['body_parser'] = falsy_parser
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

%w[nil false].each do |message_body|
  Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: message_body)
end

sleep 1

poll_queues_until { DT[:performed].size >= 2 }

assert_equal([['false', false], ['nil', nil]], DT[:performed].sort_by(&:first))
assert_equal(2, DT[:parsed_message_ids].size)
assert_equal(2, DT[:parsed_message_ids].uniq.size)
