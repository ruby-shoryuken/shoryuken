# frozen_string_literal: true

# This spec tests that with cache_visibility_timeout on, Shoryuken reads the queue VisibilityTimeout from SQS once
# and keeps that value until restart.
#
# Each job runs 2.5s with auto_visibility_timeout. After the queue VisibilityTimeout changes from 2s to 4s, the next
# job is still extended by 2s and Timing still warns that it exceeded the 2s visibility timeout.

module QueueAttributesSpy
  def get_queue_attributes(params = {}, options = {})
    DT[:attribute_reads] << params[:queue_url]
    super
  end
end

module ExtensionSpy
  def change_visibility(options)
    DT[:extensions] << [body, options[:visibility_timeout]]
    super
  end
end

Aws::SQS::Client.prepend(QueueAttributesSpy)
Shoryuken::Message.prepend(ExtensionSpy)

def register_slow_worker(queue)
  Shoryuken.add_group('default', 1)
  Shoryuken.add_queue(queue, 1, 'default')

  worker = Class.new do
    include Shoryuken::Worker

    shoryuken_options auto_visibility_timeout: true, auto_delete: true

    def perform(_sqs_msg, _body)
      sleep 2.5
    end
  end
  worker.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker)
end

setup_sqs

Shoryuken.cache_visibility_timeout = true

log = StringIO.new
Shoryuken.logger = Logger.new(log)

with_queue_and_dir(attributes: { 'VisibilityTimeout' => '2' }) do |queue, _dir|
  register_slow_worker(queue)

  sqs_queue = Shoryuken::Client.queues(queue)
  sqs_queue.send_message(message_body: 'first')
  DT[:attribute_reads].clear

  changed = false
  poll_queues_until(timeout: 30) do
    # Timing reads the visibility timeout before it logs "completed in: "
    if !changed && log.string.include?('completed in: ')
      Shoryuken::Client.sqs.set_queue_attributes(queue_url: sqs_queue.url, attributes: { 'VisibilityTimeout' => '4' })
      sqs_queue.send_message(message_body: 'second')
      changed = true
    end

    log.string.scan('completed in: ').size >= 2
  end

  reads = DT[:attribute_reads].count(sqs_queue.url)
  extensions = DT[:extensions].group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

  assert_equal(1, reads, "the visibility timeout must be read once, got #{reads} GetQueueAttributes calls")
  assert(extensions['first'].any?, "'first' must be extended, got #{extensions}")
  assert(extensions['second'].any?, "'second' must be extended, got #{extensions}")
  assert(extensions.values.flatten.all?(2), "extensions must keep the cached 2s, got #{extensions}")
  assert_equal(2, log.string.scan('exceeded the queue visibility timeout by').size, log.string)
end
