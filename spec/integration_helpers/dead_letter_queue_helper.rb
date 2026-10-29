# frozen_string_literal: true

# Queues with a redrive policy to a dead letter queue
module DeadLetterQueueHelper
  # Creates dlq_name and queue_name, which moves a message to dlq_name after 2 receives (with fifo: both are FIFO
  # queues with content-based deduplication)
  def create_queue_with_dlq(queue_name, dlq_name, attributes: {}, fifo: false)
    create_queue = fifo ? method(:create_fifo_queue) : method(:create_test_queue)
    create_queue.call(dlq_name)

    dlq_arn = Shoryuken::Client.sqs.get_queue_attributes(
      queue_url: Shoryuken::Client.sqs.get_queue_url(queue_name: dlq_name).queue_url,
      attribute_names: ['QueueArn']
    ).attributes['QueueArn']

    redrive_policy = { maxReceiveCount: 2, deadLetterTargetArn: dlq_arn }.to_json
    create_queue.call(queue_name, attributes: { 'RedrivePolicy' => redrive_policy }.merge(attributes))
  end
end
