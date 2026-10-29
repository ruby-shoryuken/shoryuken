# frozen_string_literal: true

# Queues with a redrive policy to a dead letter queue
module DeadLetterQueueHelper
  # Creates dlq_name and queue_name, which moves a message to dlq_name after max_receive_count receives (with fifo:
  # both are FIFO queues with content-based deduplication)
  def create_queue_with_dlq(queue_name, dlq_name, max_receive_count:, attributes: {}, fifo: false)
    fifo ? create_fifo_queue(dlq_name) : create_test_queue(dlq_name)

    dlq_arn = Shoryuken::Client.sqs.get_queue_attributes(
      queue_url: Shoryuken::Client.sqs.get_queue_url(queue_name: dlq_name).queue_url,
      attribute_names: ['QueueArn']
    ).attributes['QueueArn']

    attributes = {
      'RedrivePolicy' => { maxReceiveCount: max_receive_count, deadLetterTargetArn: dlq_arn }.to_json
    }.merge(attributes)
    fifo ? create_fifo_queue(queue_name, attributes: attributes) : create_test_queue(queue_name, attributes: attributes)
  end
end
