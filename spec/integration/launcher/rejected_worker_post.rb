# frozen_string_literal: true

require 'timeout'

def expect_rejected_worker_post_released(executor_class, rejection)
  DT.clear

  executor = rejecting_executor(executor_class, rejection)
  Shoryuken.define_singleton_method(:launcher_executor) { executor }

  queue_name = DT.queue
  # Far longer than the spec runs, so the message can only reappear if released.
  create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '60' })
  Shoryuken.add_group('default', 1)
  Shoryuken.add_queue(queue_name, 1, 'default')

  worker = Class.new do
    include Shoryuken::Worker

    shoryuken_options auto_delete: true

    def perform(sqs_msg, _body)
      DT[:processed] << sqs_msg.message_id
    end
  end

  worker.get_shoryuken_options['queue'] = queue_name
  Shoryuken.register_worker(queue_name, worker)

  queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url
  Shoryuken::Client.sqs.send_message(queue_url: queue_url, message_body: 'rejected post')

  launcher = Shoryuken::Launcher.new
  launcher.start

  # This executor rejects every worker post, so each rejection releases the message
  # and the next poll fetches it again. Stop after the first one to end that loop.
  Timeout.timeout(15) { sleep 0.05 until DT[:rejected].size >= 1 }
  Timeout.timeout(20) { launcher.stop! }

  received = Shoryuken::Client.sqs.receive_message(queue_url: queue_url, wait_time_seconds: 3).messages

  assert_equal(
    1,
    received.size,
    'a message whose worker post was rejected must be released at once, not stay in flight for the visibility timeout'
  )
  assert_equal('rejected post', received.first.body)
  assert(DT[:processed].empty?, 'a message whose worker post was rejected must not be processed')
end

def rejecting_executor(executor_class, rejection)
  Class.new(executor_class) do
    define_method(:post) do |*args, &block|
      if caller_locations.any? { |l| l.base_label == 'assign' && l.path.end_with?('shoryuken/manager.rb') }
        DT[:rejected] << true
        raise rejection
      end

      super(*args, &block)
    end
  end.new
end
