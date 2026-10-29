# frozen_string_literal: true

# Message counts of a queue
module QueueStateHelper
  # Messages in a queue, visible and in flight, plus delayed ones with delayed: true
  def queue_size(queue_name, delayed: false)
    queue_counts(queue_name, delayed: delayed).values.sum
  end

  # Visible and in-flight message counts of a queue, as { visible:, in_flight: },
  # plus :delayed with delayed: true
  def queue_counts(queue_name, delayed: false)
    queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
    attribute_names = %w[ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible]
    attribute_names << 'ApproximateNumberOfMessagesDelayed' if delayed

    attributes = Shoryuken::Client.sqs.get_queue_attributes(
      queue_url: queue_url,
      attribute_names: attribute_names
    ).attributes

    counts = {
      visible: attributes['ApproximateNumberOfMessages'].to_i,
      in_flight: attributes['ApproximateNumberOfMessagesNotVisible'].to_i
    }
    counts[:delayed] = attributes['ApproximateNumberOfMessagesDelayed'].to_i if delayed
    counts
  end
end
