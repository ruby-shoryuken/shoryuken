# frozen_string_literal: true

# This spec tests a message that is not an ActiveJob payload on a queue served
# by the ActiveJob JobWrapper. The JSON parse error reaches the exception
# handlers, the message is not deleted, and the jobs after it still run.
#
# Regression: #192, a plain-text message on an ActiveJob queue killed the
# processor ("Process died").

setup_sqs
setup_active_job

queue_name = DT.queue
create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })

class MalformedBodyNeighbourJob < ActiveJob::Base
  def perform(label)
    DT[:performed] << label
  end
end

MalformedBodyNeighbourJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

Shoryuken.exception_handlers = [
  ->(error, queue, sqs_msg) { DT[:handled] << [queue, error.class, sqs_msg.body] }
]

Shoryuken::Client.queues(queue_name).send_message(message_body: 'msg 1')

MalformedBodyNeighbourJob.perform_later('after')

poll_queues_until(timeout: 20) { DT[:performed].size >= 1 && DT[:handled].size >= 2 }

assert_equal(['after'], DT[:performed])
assert_equal([[queue_name, JSON::ParserError, 'msg 1']], DT[:handled].uniq)
assert_equal(1, queue_size(queue_name), 'the plain-text message must not be deleted')

delete_test_queue(queue_name)
