# frozen_string_literal: true

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

def process_across_visibility_timeout_change(cache:)
  Shoryuken.cache_visibility_timeout = cache

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

    [reads, extensions, log.string]
  end
ensure
  Shoryuken.cache_visibility_timeout = false
end

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
